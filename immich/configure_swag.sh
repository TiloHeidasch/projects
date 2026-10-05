#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env"
FORCE=false

declare -A ENV_VALUES=()
declare -A ENV_SEEN=()

die() {
  printf 'configure_swag.sh: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: bash %s [--force]\n' "${BASH_SOURCE[0]}"
}

while (($# > 0)); do
  case "$1" in
    --force)
      FORCE=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "unknown argument: $1"
      ;;
  esac
  shift
done

parse_env_file() {
  local file="$1"
  local line
  local line_number=0
  local key
  local value

  [[ -r "$file" ]] || die "missing readable .env: ${file}"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    [[ "$line" == *$'\r' ]] && line="${line%$'\r'}"

    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || \
      die "invalid literal KEY=VALUE line in ${file}:${line_number}"

    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    case "$key" in
      TUNNEL_TOKEN|SWAG_PUID|SWAG_PGID|SWAG_TZ|SWAG_URL|SWAG_CONFIG|SWAG_EMAIL|SWAG_BIND_ADDRESS|SWAG_HOST_PORT|CF_DNS_API_TOKEN|IMMICH_VERSION|IMMICH_DATA|DB_DATA|MODEL_CACHE|DB_USERNAME|DB_DATABASE_NAME|DB_PASSWORD)
        ;;
      *)
        die "unknown key ${key} in ${file}:${line_number}; update .env.example or remove it"
        ;;
    esac

    [[ -z "${ENV_SEEN[$key]+present}" ]] || \
      die "duplicate key ${key} in ${file}:${line_number}"
    ENV_SEEN["$key"]=1
    ENV_VALUES["$key"]="$value"
  done < "$file"
}

require_value() {
  local key="$1"
  local value

  [[ -n "${ENV_VALUES[$key]+present}" ]] || die "missing required key ${key} in ${ENV_FILE}"
  value="${ENV_VALUES[$key]}"
  [[ -n "$value" ]] || die "required key ${key} is empty in ${ENV_FILE}"
  [[ "$value" != "your_value_here" ]] || die "${key} still contains the example placeholder"
}

validate_hostname() {
  local hostname="$1"
  local description="$2"
  local label
  local -a labels

  [[ "$hostname" != *[[:space:]/]* ]] || die "${description} must be a hostname"
  [[ "$hostname" != .* && "$hostname" != *. ]] || die "${description} has an empty hostname label"
  [[ "$hostname" != *..* ]] || die "${description} has an empty hostname label"
  [[ ${#hostname} -le 253 ]] || die "${description} is too long"

  IFS='.' read -r -a labels <<< "$hostname"
  ((${#labels[@]} > 0)) || die "${description} must not be empty"
  for label in "${labels[@]}"; do
    [[ ${#label} -le 63 ]] || die "${description} has an overlong label"
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || \
      die "${description} contains an invalid hostname label: ${label}"
  done
}

validate_ipv4() {
  local address="$1"
  local description="$2"
  local octet
  local -a octets

  IFS='.' read -r -a octets <<< "$address"
  ((${#octets[@]} == 4)) || die "${description} must be an IPv4 address"
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]{1,3}$ ]] || die "${description} must be an IPv4 address"
    ((10#$octet <= 255)) || die "${description} must be an IPv4 address"
  done
}

parse_env_file "$ENV_FILE"

for required in \
  SWAG_PUID \
  SWAG_PGID \
  SWAG_TZ \
  SWAG_URL \
  SWAG_CONFIG \
  SWAG_EMAIL \
  SWAG_BIND_ADDRESS \
  SWAG_HOST_PORT \
  CF_DNS_API_TOKEN; do
  require_value "$required"
done

SWAG_PUID_VALUE="${ENV_VALUES[SWAG_PUID]}"
SWAG_PGID_VALUE="${ENV_VALUES[SWAG_PGID]}"
SWAG_URL_VALUE="${ENV_VALUES[SWAG_URL]}"
SWAG_CONFIG_VALUE="${ENV_VALUES[SWAG_CONFIG]}"
SWAG_EMAIL_VALUE="${ENV_VALUES[SWAG_EMAIL]}"
SWAG_BIND_ADDRESS_VALUE="${ENV_VALUES[SWAG_BIND_ADDRESS]}"
SWAG_HOST_PORT_VALUE="${ENV_VALUES[SWAG_HOST_PORT]}"
CF_DNS_API_TOKEN_VALUE="${ENV_VALUES[CF_DNS_API_TOKEN]}"

[[ "$SWAG_PUID_VALUE" =~ ^[0-9]+$ ]] || die "SWAG_PUID must be numeric"
[[ "$SWAG_PGID_VALUE" =~ ^[0-9]+$ ]] || die "SWAG_PGID must be numeric"
[[ "$SWAG_CONFIG_VALUE" == /* && "$SWAG_CONFIG_VALUE" != "/" ]] || \
  die "SWAG_CONFIG must be an absolute directory other than /"
[[ "$SWAG_EMAIL_VALUE" != *[[:space:]]* ]] || die "SWAG_EMAIL must not contain whitespace"
[[ "$CF_DNS_API_TOKEN_VALUE" != *[[:space:]]* ]] || die "CF_DNS_API_TOKEN must not contain whitespace"
[[ "$SWAG_HOST_PORT_VALUE" =~ ^[0-9]+$ ]] || die "SWAG_HOST_PORT must be numeric"
((10#$SWAG_HOST_PORT_VALUE >= 1 && 10#$SWAG_HOST_PORT_VALUE <= 65535)) || \
  die "SWAG_HOST_PORT must be between 1 and 65535"

validate_ipv4 "$SWAG_BIND_ADDRESS_VALUE" "SWAG_BIND_ADDRESS"

BASE_DOMAIN="${SWAG_URL_VALUE%.}"
[[ "$BASE_DOMAIN" == *.* ]] || die "SWAG_URL must be a domain name"
validate_hostname "$BASE_DOMAIN" "SWAG_URL"

SUBDOMAINS=(photo photo2)
for subdomain in "${SUBDOMAINS[@]}"; do
  validate_hostname "${subdomain}.${BASE_DOMAIN}" "generated hostname"
done

DNS_DIR="${SWAG_CONFIG_VALUE}/dns-conf"
NGINX_DIR="${SWAG_CONFIG_VALUE}/nginx"
SITE_CONFS_DIR="${NGINX_DIR}/site-confs"
DNS_FILE="${DNS_DIR}/cloudflare.ini"
IMMICH_FILE="${SITE_CONFS_DIR}/immich.conf"
DEFAULT_FILE="${SITE_CONFS_DIR}/default.conf"

if ! $FORCE; then
  for generated in "$DNS_FILE" "$IMMICH_FILE" "$DEFAULT_FILE"; do
    [[ ! -e "$generated" && ! -L "$generated" ]] || \
      die "refusing to overwrite ${generated}; rerun with --force"
  done
fi

umask 077
mkdir -p "$DNS_DIR" "$SITE_CONFS_DIR"
chmod 700 "$SWAG_CONFIG_VALUE" "$DNS_DIR" "$NGINX_DIR" "$SITE_CONFS_DIR"

if ((EUID == 0)); then
  chown "${SWAG_PUID_VALUE}:${SWAG_PGID_VALUE}" \
    "$SWAG_CONFIG_VALUE" "$DNS_DIR" "$NGINX_DIR" "$SITE_CONFS_DIR"
fi

tmp_dns=''
tmp_immich=''
tmp_default=''
cleanup() {
  [[ -z "$tmp_dns" ]] || rm -f "$tmp_dns"
  [[ -z "$tmp_immich" ]] || rm -f "$tmp_immich"
  [[ -z "$tmp_default" ]] || rm -f "$tmp_default"
}
trap cleanup EXIT

tmp_dns="$(mktemp "${DNS_DIR}/.cloudflare.ini.XXXXXX")"
tmp_immich="$(mktemp "${SITE_CONFS_DIR}/.immich.conf.XXXXXX")"
tmp_default="$(mktemp "${SITE_CONFS_DIR}/.default.conf.XXXXXX")"
chmod 600 "$tmp_dns"
chmod 640 "$tmp_immich" "$tmp_default"

printf 'dns_cloudflare_api_token = %s\n' "$CF_DNS_API_TOKEN_VALUE" > "$tmp_dns"

{
  printf '%s\n' '# Generated by configure_swag.sh; do not edit this file directly.'
  printf '%s\n' '# Exact-host Immich virtual host.'
  printf '\n'
  printf 'server {\n'
  printf '    listen 443 ssl;\n'
  printf '    listen [::]:443 ssl;\n'
  printf '    server_name'
  for subdomain in "${SUBDOMAINS[@]}"; do
    printf ' %s.%s' "$subdomain" "$BASE_DOMAIN"
  done
  printf ';\n\n'
  printf '    include /config/nginx/ssl.conf;\n'
  printf '    client_max_body_size 50000M;\n'
  printf '    client_body_buffer_size 1024k;\n'
  printf '    send_timeout 600s;\n\n'
  printf '    location / {\n'
  printf '        resolver 127.0.0.11 valid=30s ipv6=off;\n'
  printf '        set $immich_upstream http://immich-server:2283;\n'
  printf '        proxy_pass $immich_upstream;\n'
  printf '        proxy_http_version 1.1;\n'
  printf '        proxy_set_header Host $host;\n'
  printf '        proxy_set_header X-Real-IP $remote_addr;\n'
  printf '        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n'
  printf '        proxy_set_header X-Forwarded-Proto $scheme;\n'
  printf '        proxy_set_header X-Forwarded-Host $host;\n'
  printf '        proxy_set_header X-Forwarded-Port $server_port;\n'
  printf '        proxy_set_header Upgrade $http_upgrade;\n'
  printf '        proxy_set_header Connection "upgrade";\n'
  printf '        proxy_request_buffering off;\n'
  printf '        proxy_buffering off;\n'
  printf '        proxy_redirect off;\n'
  printf '        proxy_connect_timeout 600s;\n'
  printf '        proxy_read_timeout 600s;\n'
  printf '        proxy_send_timeout 600s;\n'
  printf '    }\n'
  printf '}\n\n'
} > "$tmp_immich"

{
  printf '%s\n' '# Generated by configure_swag.sh; do not edit this file directly.'
  printf 'server {\n'
  printf '    listen 443 ssl default_server;\n'
  printf '    listen [::]:443 ssl default_server;\n'
  printf '    server_name _;\n'
  printf '    include /config/nginx/ssl.conf;\n'
  printf '    return 444;\n'
  printf '}\n'
} > "$tmp_default"

if ((EUID == 0)); then
  chown "${SWAG_PUID_VALUE}:${SWAG_PGID_VALUE}" "$tmp_dns" "$tmp_immich" "$tmp_default"
fi

mv -f "$tmp_dns" "$DNS_FILE"
tmp_dns=''
mv -f "$tmp_immich" "$IMMICH_FILE"
tmp_immich=''
mv -f "$tmp_default" "$DEFAULT_FILE"
tmp_default=''

printf 'Generated %s, %s, and %s\n' "$DNS_FILE" "$IMMICH_FILE" "$DEFAULT_FILE"
printf 'After --force, recreate/restart SWAG and run: docker compose exec swag nginx -t\n'
