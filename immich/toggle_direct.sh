#!/usr/bin/env bash
set -euo pipefail

usage() {
    printf 'Usage: bash immich/toggle_direct.sh direct --ready [--skip-wan-check] [--dry-run]\n' >&2
    printf '       bash immich/toggle_direct.sh tunnel [--dry-run]\n' >&2
}

die() {
    printf 'toggle_direct.sh: %s\n' "$*" >&2
    exit 1
}

if (( $# < 1 )); then
    usage
    exit 2
fi

MODE=$1
shift
case "$MODE" in
    direct|tunnel)
        ;;
    *)
        usage
        exit 2
        ;;
esac

DRY_RUN=0
READY=0
SKIP_WAN_CHECK=0
while (( $# > 0 )); do
    case "$1" in
        --dry-run)
            (( DRY_RUN == 0 )) || die 'duplicate --dry-run flag'
            DRY_RUN=1
            ;;
        --ready)
            [[ $MODE == direct ]] || die '--ready is only valid in direct mode'
            (( READY == 0 )) || die 'duplicate --ready flag'
            READY=1
            ;;
        --skip-wan-check)
            [[ $MODE == direct ]] || die '--skip-wan-check is only valid in direct mode'
            (( SKIP_WAN_CHECK == 0 )) || die 'duplicate --skip-wan-check flag'
            SKIP_WAN_CHECK=1
            ;;
        *)
            usage
            exit 2
            ;;
    esac
    shift
done

if [[ $MODE == direct && $READY -ne 1 ]]; then
    die 'direct mode requires explicit --ready acknowledgement'
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
MAIN_ENV="$SCRIPT_DIR/.env"

[[ -r "$MAIN_ENV" ]] || die "required environment file is not readable: $MAIN_ENV"

# This parser intentionally never evaluates values. Unknown, syntactically valid
# assignments are ignored so the compose .env can contain unrelated settings.
MAIN_SWAG_URL=''
MAIN_IMMICH_DIRECT_ENV=''
DIRECT_CF_DNS_API_TOKEN=''
DIRECT_CF_ZONE_ID=''
DIRECT_CF_TUNNEL_TARGET=''
DIRECT_IMMICH_DIRECT_IPV4=''
SEEN_MAIN_SWAG_URL=0
SEEN_MAIN_IMMICH_DIRECT_ENV=0
SEEN_DIRECT_CF_DNS_API_TOKEN=0
SEEN_DIRECT_CF_ZONE_ID=0
SEEN_DIRECT_CF_TUNNEL_TARGET=0
SEEN_DIRECT_IMMICH_DIRECT_IPV4=0

parse_env_file() {
    local file=$1
    local scope=$2
    local line
    local line_number=0
    local key
    local value

    while IFS= read -r line || [[ -n $line ]]; do
        line_number=$((line_number + 1))
        [[ $line != *$'\r'* ]] || die "$file:$line_number contains an unsupported carriage return"

        if [[ $line =~ ^[[:space:]]*$ || $line =~ ^[[:space:]]*# ]]; then
            continue
        fi
        if [[ ! $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            die "$file:$line_number is not a literal KEY=VALUE assignment"
        fi

        key=${BASH_REMATCH[1]}
        value=${BASH_REMATCH[2]}
        case "$scope:$key" in
            main:SWAG_URL)
                (( SEEN_MAIN_SWAG_URL == 0 )) || die "$file:$line_number duplicates SWAG_URL"
                SEEN_MAIN_SWAG_URL=1
                MAIN_SWAG_URL=$value
                ;;
            main:IMMICH_DIRECT_ENV)
                (( SEEN_MAIN_IMMICH_DIRECT_ENV == 0 )) || die "$file:$line_number duplicates IMMICH_DIRECT_ENV"
                SEEN_MAIN_IMMICH_DIRECT_ENV=1
                MAIN_IMMICH_DIRECT_ENV=$value
                ;;
            direct:CF_DNS_API_TOKEN)
                (( SEEN_DIRECT_CF_DNS_API_TOKEN == 0 )) || die "$file:$line_number duplicates CF_DNS_API_TOKEN"
                SEEN_DIRECT_CF_DNS_API_TOKEN=1
                DIRECT_CF_DNS_API_TOKEN=$value
                ;;
            direct:CF_ZONE_ID)
                (( SEEN_DIRECT_CF_ZONE_ID == 0 )) || die "$file:$line_number duplicates CF_ZONE_ID"
                SEEN_DIRECT_CF_ZONE_ID=1
                DIRECT_CF_ZONE_ID=$value
                ;;
            direct:CF_TUNNEL_TARGET)
                (( SEEN_DIRECT_CF_TUNNEL_TARGET == 0 )) || die "$file:$line_number duplicates CF_TUNNEL_TARGET"
                SEEN_DIRECT_CF_TUNNEL_TARGET=1
                DIRECT_CF_TUNNEL_TARGET=$value
                ;;
            direct:IMMICH_DIRECT_IPV4)
                (( SEEN_DIRECT_IMMICH_DIRECT_IPV4 == 0 )) || die "$file:$line_number duplicates IMMICH_DIRECT_IPV4"
                SEEN_DIRECT_IMMICH_DIRECT_IPV4=1
                DIRECT_IMMICH_DIRECT_IPV4=$value
                ;;
            main:CF_DNS_API_TOKEN|main:CF_ZONE_ID|main:CF_TUNNEL_TARGET|main:IMMICH_DIRECT_IPV4)
                die "$file:$line_number puts $key in the wrong environment file"
                ;;
            direct:SWAG_URL|direct:IMMICH_DIRECT_ENV)
                die "$file:$line_number puts $key in the wrong environment file"
                ;;
            *)
                ;;
        esac
    done < "$file"
}

parse_env_file "$MAIN_ENV" main

(( SEEN_MAIN_SWAG_URL == 1 )) || die "SWAG_URL is missing from $MAIN_ENV"
(( SEEN_MAIN_IMMICH_DIRECT_ENV == 1 )) || die "IMMICH_DIRECT_ENV is missing from $MAIN_ENV"

DIRECT_ENV=$MAIN_IMMICH_DIRECT_ENV
if [[ $DIRECT_ENV != /* || $DIRECT_ENV == / ]]; then
    die 'IMMICH_DIRECT_ENV must be an absolute non-root path'
fi
[[ -r "$DIRECT_ENV" ]] || die "required environment file is not readable: $DIRECT_ENV"

parse_env_file "$DIRECT_ENV" direct

(( SEEN_DIRECT_CF_DNS_API_TOKEN == 1 )) || die "CF_DNS_API_TOKEN is missing from $DIRECT_ENV"
(( SEEN_DIRECT_CF_ZONE_ID == 1 )) || die "CF_ZONE_ID is missing from $DIRECT_ENV"
(( SEEN_DIRECT_CF_TUNNEL_TARGET == 1 )) || die "CF_TUNNEL_TARGET is missing from $DIRECT_ENV"
(( SEEN_DIRECT_IMMICH_DIRECT_IPV4 == 1 )) || die "IMMICH_DIRECT_IPV4 is missing from $DIRECT_ENV"

for command_name in curl jq; do
    command -v "$command_name" >/dev/null 2>&1 || die "required command not found: $command_name"
done

lowercase() {
    LC_ALL=C tr '[:upper:]' '[:lower:]' <<< "$1"
}

is_placeholder() {
    local value=$1
    local lower

    lower=$(lowercase "$value")
    case "$lower" in
        your_value|your_value_here|your-token-here|your_token_here|your-value-here|change_me|change-me|changeme|replace_me|replace-me|insert_here|set_me|placeholder|example|example.com|todo|none|null)
            return 0
            ;;
    esac
    if [[ $value == *'<'* || $value == *'>'* || $value == *'${'* || $value == *'$('* ]]; then
        return 0
    fi
    return 1
}

is_dns_name() {
    local value=$1

    if [[ -z $value || ${#value} -gt 253 ]]; then
        return 1
    fi
    [[ $value =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$ ]]
}

is_ipv4() {
    local value=$1
    local IFS=.
    local -a octets
    local octet

    [[ $value =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    read -r -a octets <<< "$value"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    for octet in "${octets[@]}"; do
        if (( 10#$octet > 255 )); then
            return 1
        fi
    done
    return 0
}

is_globally_routable_ipv4() {
    local value=$1
    local IFS=.
    local -a octets
    local a b c

    is_ipv4 "$value" || return 1
    read -r -a octets <<< "$value"
    a=$((10#${octets[0]}))
    b=$((10#${octets[1]}))
    c=$((10#${octets[2]}))

    (( a != 0 )) || return 1
    (( a != 10 )) || return 1
    (( a != 127 )) || return 1
    (( a < 224 )) || return 1
    (( a != 100 || b < 64 || b > 127 )) || return 1
    (( a != 169 || b != 254 )) || return 1
    (( a != 172 || b < 16 || b > 31 )) || return 1
    (( a != 192 || b != 0 )) || return 1
    (( a != 192 || b != 2 )) || return 1
    (( a != 192 || b != 88 || c != 99 )) || return 1
    (( a != 192 || b != 168 )) || return 1
    (( a != 198 || b < 18 || b > 19 )) || return 1
    (( a != 198 || b != 51 || c != 100 )) || return 1
    (( a != 203 || b != 0 || c != 113 )) || return 1
    return 0
}

SWAG_URL=$(lowercase "$MAIN_SWAG_URL")
CF_DNS_API_TOKEN=$DIRECT_CF_DNS_API_TOKEN
CF_ZONE_ID=$(lowercase "$DIRECT_CF_ZONE_ID")
CF_TUNNEL_TARGET=$(lowercase "$DIRECT_CF_TUNNEL_TARGET")
IMMICH_DIRECT_IPV4=$DIRECT_IMMICH_DIRECT_IPV4

if is_placeholder "$DIRECT_ENV"; then
    die 'IMMICH_DIRECT_ENV contains a placeholder value'
fi
if is_placeholder "$SWAG_URL"; then
    die 'SWAG_URL contains a placeholder value'
fi
if is_placeholder "$CF_DNS_API_TOKEN"; then
    die 'CF_DNS_API_TOKEN contains a placeholder value'
fi
if is_placeholder "$CF_ZONE_ID"; then
    die 'CF_ZONE_ID contains a placeholder value'
fi
if is_placeholder "$CF_TUNNEL_TARGET"; then
    die 'CF_TUNNEL_TARGET contains a placeholder value'
fi
if is_placeholder "$IMMICH_DIRECT_IPV4"; then
    die 'IMMICH_DIRECT_IPV4 contains a placeholder value'
fi

is_dns_name "$SWAG_URL" || die 'SWAG_URL must be a lower-case DNS name without a scheme or trailing dot'
[[ $CF_DNS_API_TOKEN =~ ^[A-Za-z0-9_-]+$ ]] || die 'CF_DNS_API_TOKEN contains unsupported whitespace or characters'
[[ $CF_ZONE_ID =~ ^[a-f0-9]{32}$ ]] || die 'CF_ZONE_ID must be a 32-character lower-case hexadecimal ID'
[[ $CF_TUNNEL_TARGET =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.cfargotunnel\.com$ ]] || \
    die 'CF_TUNNEL_TARGET must be <UUID>.cfargotunnel.com'

is_globally_routable_ipv4 "$IMMICH_DIRECT_IPV4" || die 'IMMICH_DIRECT_IPV4 must be globally routable IPv4'

FQDNS=("photo.$SWAG_URL" "photo2.$SWAG_URL")
for fqdn in "${FQDNS[@]}"; do
    is_dns_name "$fqdn" || die "derived FQDN is invalid: $fqdn"
done

if [[ $MODE == direct ]]; then
    printf 'Prerequisite (--ready): SWAG, its DNS-01 certificate, the Immich upstream, router TCP 443, and an external HTTPS test are already working.\n'
    if (( SKIP_WAN_CHECK )); then
        printf 'WAN check skipped (--skip-wan-check) for an exceptional NAT setup.\n'
    fi
else
    printf 'Reminder: close router TCP 443 only after DNS propagation; no router automation is performed.\n'
fi

umask 077
CURL_CONFIG=$(mktemp "${TMPDIR:-/tmp}/toggle_direct.curl.XXXXXX") || die 'could not create a temporary curl config'
cleanup() {
    rm -f "$CURL_CONFIG"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
chmod 600 "$CURL_CONFIG" || die 'could not secure the temporary curl config'

# The token is written only to this 0600 curl config, never passed as an argv value.
printf 'header = "Authorization: Bearer %s"\n' "$CF_DNS_API_TOKEN" > "$CURL_CONFIG"

API_BASE='https://api.cloudflare.com/client/v4'
DNS_RECORDS_URL="$API_BASE/zones/$CF_ZONE_ID/dns_records"
BATCH_URL="$DNS_RECORDS_URL/batch"

fetch_exact_record() {
    local name=$1
    local response
    local count

    if ! response=$(curl -q \
        --config "$CURL_CONFIG" \
        --fail-with-body \
        --silent \
        --show-error \
        --connect-timeout 5 \
        --max-time 20 \
        --get \
        --header 'Accept: application/json' \
        --data-urlencode "name=$name" \
        "$DNS_RECORDS_URL"); then
        return 10
    fi
    if ! jq -e '.success == true' <<< "$response" >/dev/null 2>&1; then
        return 11
    fi
    if ! count=$(jq -er --arg name "$name" '
        if (.result | type) != "array" then
            error("result is not an array")
        else
            [.result[] | select(.name == $name)] | length
        end
    ' <<< "$response" 2>/dev/null); then
        return 12
    fi
    [[ $count == 1 ]] || return 13
    jq -ce --arg name "$name" '[.result[] | select(.name == $name)][0]' <<< "$response" 2>/dev/null
}

record_has_fields() {
    local record=$1
    local expected_id=$2
    local expected_name=$3
    local expected_type=$4
    local expected_content=$5
    local expected_proxied=$6

    jq -e \
        --arg id "$expected_id" \
        --arg name "$expected_name" \
        --arg type "$expected_type" \
        --arg content "$expected_content" \
        --argjson proxied "$expected_proxied" \
        'type == "object"
         and .id == $id
         and .name == $name
         and .type == $type
         and .content == $content
         and .proxied == $proxied' <<< "$record" >/dev/null 2>&1
}

record_has_desired_fields() {
    local record=$1
    local expected_id=$2
    local expected_name=$3
    local expected_type=$4
    local expected_content=$5
    local expected_proxied=$6
    local expected_ttl=$7

    record_has_fields "$record" "$expected_id" "$expected_name" "$expected_type" "$expected_content" "$expected_proxied" || return 1
    jq -e --argjson ttl "$expected_ttl" '.ttl == $ttl' <<< "$record" >/dev/null 2>&1
}

record_id_from_json() {
    jq -er '.id | select(type == "string" and length > 0)' <<< "$1" 2>/dev/null
}

build_desired_payload() {
    local current=$1
    local name=$2
    local type=$3
    local content=$4
    local proxied=$5
    local ttl=$6

    jq -cn \
        --argjson current "$current" \
        --arg name "$name" \
        --arg type "$type" \
        --arg content "$content" \
        --argjson proxied "$proxied" \
        --argjson ttl "$ttl" \
        '
        ($current
         | {
             id: .id,
             name: $name,
             type: $type,
             content: $content,
             proxied: $proxied,
             ttl: $ttl
           }
           + (if (.comment? | type) == "string" then {comment: .comment} else {} end)
           + (if (.tags? | type) == "array" then {tags: .tags} else {} end)
           + (if ((.settings? | type) == "object" and .type == $type)
              then {settings: .settings}
              else {}
              end))'
}

check_desired_state() {
    local index
    local record

    for index in 0 1; do
        if ! record=$(fetch_exact_record "${FQDNS[$index]}"); then
            return 1
        fi
        if ! record_has_desired_fields \
            "$record" \
            "${RECORD_IDS[$index]}" \
            "${FQDNS[$index]}" \
            "$DESIRED_TYPE" \
            "$DESIRED_CONTENT" \
            "$DESIRED_PROXIED" \
            "$DESIRED_TTL"; then
            return 1
        fi
    done
    return 0
}

if [[ $MODE == direct ]]; then
    DESIRED_TYPE=A
    DESIRED_CONTENT=$IMMICH_DIRECT_IPV4
    DESIRED_PROXIED=false
    DESIRED_TTL=60
    CURRENT_TYPE=CNAME
    CURRENT_CONTENT=$CF_TUNNEL_TARGET
    CURRENT_PROXIED=true
else
    DESIRED_TYPE=CNAME
    DESIRED_CONTENT=$CF_TUNNEL_TARGET
    DESIRED_PROXIED=true
    DESIRED_TTL=1
    CURRENT_TYPE=A
    CURRENT_CONTENT=$IMMICH_DIRECT_IPV4
    CURRENT_PROXIED=false
fi

if [[ $MODE == direct && $SKIP_WAN_CHECK -eq 0 ]]; then
    if ! public_ip=$(curl -q \
        --fail-with-body \
        --silent \
        --show-error \
        --connect-timeout 5 \
        --max-time 15 \
        --proto '=https' \
        --tlsv1.2 \
        'https://api.ipify.org'); then
        die 'could not retrieve the current public IPv4 for the WAN check'
    fi
    public_ip=${public_ip//$'\r'/}
    is_globally_routable_ipv4 "$public_ip" || die 'public IPv4 endpoint did not return a globally routable IPv4'
    [[ $public_ip == "$IMMICH_DIRECT_IPV4" ]] || die 'IMMICH_DIRECT_IPV4 does not match the current public IPv4'
    printf 'WAN check passed.\n'
fi

RECORD_JSONS=()
RECORD_IDS=()
for index in 0 1; do
    fqdn=${FQDNS[$index]}
    if record=$(fetch_exact_record "$fqdn"); then
        :
    else
        fetch_status=$?
        case "$fetch_status" in
            13) die "expected exactly one exact DNS record for $fqdn" ;;
            10) die "Cloudflare DNS lookup failed for $fqdn" ;;
            *) die "Cloudflare returned an invalid DNS record response for $fqdn" ;;
        esac
    fi

    record_id=$(record_id_from_json "$record") || die "Cloudflare returned no usable record ID for $fqdn"
    [[ $record_id =~ ^[A-Za-z0-9_-]+$ ]] || die "Cloudflare returned an unsafe record ID for $fqdn"
    if ! record_has_fields "$record" "$record_id" "$fqdn" "$CURRENT_TYPE" "$CURRENT_CONTENT" "$CURRENT_PROXIED"; then
        die "refusing to overwrite unexpected DNS state for $fqdn"
    fi

    RECORD_JSONS+=("$record")
    RECORD_IDS+=("$record_id")
done

DESIRED_PAYLOADS=()
for index in 0 1; do
    if ! desired_payload=$(build_desired_payload \
        "${RECORD_JSONS[$index]}" \
        "${FQDNS[$index]}" \
        "$DESIRED_TYPE" \
        "$DESIRED_CONTENT" \
        "$DESIRED_PROXIED" \
        "$DESIRED_TTL"); then
        die "could not build the DNS payload for ${FQDNS[$index]}"
    fi
    DESIRED_PAYLOADS+=("$desired_payload")
done

if ! batch_payload=$(jq -cn \
    --argjson first "${DESIRED_PAYLOADS[0]}" \
    --argjson second "${DESIRED_PAYLOADS[1]}" \
    '{puts: [$first, $second]}'); then
    die 'could not build the DNS batch payload'
fi

for index in 0 1; do
    printf '%s: %s -> %s content=%s proxied=%s ttl=%s\n' \
        "$([ "$DRY_RUN" -eq 1 ] && printf 'DRY-RUN' || printf 'INTENDED')" \
        "${FQDNS[$index]}" "$DESIRED_TYPE" "$DESIRED_CONTENT" "$DESIRED_PROXIED" "$DESIRED_TTL"
done

if (( DRY_RUN )); then
    printf 'Dry run complete: both records preflighted; no POST was made.\n'
    exit 0
fi

if batch_response=$(curl -q \
    --config "$CURL_CONFIG" \
    --fail-with-body \
    --silent \
    --show-error \
    --connect-timeout 5 \
    --max-time 30 \
    --request POST \
    --header 'Accept: application/json' \
    --header 'Content-Type: application/json' \
    --data "$batch_payload" \
    "$BATCH_URL"); then
    :
else
    printf 'Batch request outcome is ambiguous; re-querying both records without retrying.\n' >&2
    if check_desired_state; then
        die 'ambiguous batch outcome: both records appear fully applied; no retry was attempted'
    else
        die 'ambiguous batch outcome: both records are not fully applied; no retry was attempted'
    fi
fi

if ! jq -e \
    --argjson expected_first "${DESIRED_PAYLOADS[0]}" \
    --argjson expected_second "${DESIRED_PAYLOADS[1]}" \
    '
    . as $root
    | [$expected_first, $expected_second] as $expected
    | (.success == true)
      and (($root.result | type) == "object")
      and (($root.result.puts | type) == "array")
      and (($root.result.puts | length) == ($expected | length))
      and all($expected[];
          . as $expected_put
          | [ $root.result.puts[]
              | select(
                  .id == $expected_put.id
                  and .name == $expected_put.name
                  and .type == $expected_put.type
                  and .content == $expected_put.content
                  and .proxied == $expected_put.proxied
                  and ((has("ttl") | not) or .ttl == $expected_put.ttl)
                  and ((($expected_put | has("comment")) | not) or (has("comment") | not) or .comment == $expected_put.comment)
                  and ((($expected_put | has("tags")) | not) or (has("tags") | not) or .tags == $expected_put.tags)
                  and ((($expected_put | has("settings")) | not) or (has("settings") | not) or .settings == $expected_put.settings)
                )
            ] | length == 1)
    ' <<< "$batch_response" >/dev/null 2>&1; then
    die 'Cloudflare returned an invalid or incomplete DNS batch result'
fi

for index in 0 1; do
    if ! record=$(fetch_exact_record "${FQDNS[$index]}"); then
        die "post-update verification lookup failed for ${FQDNS[$index]}"
    fi
    if ! record_has_desired_fields \
        "$record" \
        "${RECORD_IDS[$index]}" \
        "${FQDNS[$index]}" \
        "$DESIRED_TYPE" \
        "$DESIRED_CONTENT" \
        "$DESIRED_PROXIED" \
        "$DESIRED_TTL"; then
        die "post-update verification failed for ${FQDNS[$index]}"
    fi
done

printf 'Completed %s DNS mode for both records.\n' "$MODE"
