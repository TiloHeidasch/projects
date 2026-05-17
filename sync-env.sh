#!/usr/bin/env bash
set -euo pipefail

DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

TIMESTAMP="$(date +"%Y-%m-%d_%H-%M-%S")"
CHANGES=0

sync_stack() {
  local stack_dir="$1"
  local example="${stack_dir}/.env.example"
  local env_file="${stack_dir}/.env"
  local stack_name
  stack_name="$(basename "$stack_dir")"

  if [[ ! -f "$example" ]]; then
    return 0
  fi

  # .env does not exist → create from .env.example
  if [[ ! -f "$env_file" ]]; then
    if $DRY_RUN; then
      echo "[DRY-RUN] Would create ${stack_name}/.env from .env.example"
      CHANGES=1
      return 0
    fi
    cp "$example" "$env_file"
    echo "Created ${stack_name}/.env from .env.example"
    CHANGES=1
    return 0
  fi

  # Parse existing .env
  declare -A old_values=()
  local old_removed=()

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip empty lines and pure comments
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
      # Check if it's a #!weggefallen-* line
      if [[ "$line" =~ ^#\!weggefallen- ]]; then
        old_removed+=("$line")
      fi
      continue
    fi

    # Parse KEY=VALUE
    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      old_values["${BASH_REMATCH[1]}"]="${BASH_REMATCH[2]}"
    fi
  done < "$env_file"

  # Collect keys from .env.example
  declare -A example_keys=()

  # Build new file from .env.example
  local tmp
  tmp="$(mktemp)"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
      echo "$line" >> "$tmp"
      continue
    fi

    if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local default_val="${BASH_REMATCH[2]}"
      example_keys["$key"]=1

      if [[ -n "${old_values[$key]+x}" ]]; then
        echo "${key}=${old_values[$key]}" >> "$tmp"
      else
        echo "${key}=${default_val}" >> "$tmp"
      fi
    else
      echo "$line" >> "$tmp"
    fi
  done < "$example"

  # Append removed entries: existing old_removed (original timestamps preserved)
  for entry in "${old_removed[@]+"${old_removed[@]}"}"; do
    echo "$entry" >> "$tmp"
  done

  # Append keys that exist in old .env but not in .env.example
  for key in "${!old_values[@]}"; do
    if [[ -z "${example_keys[$key]+x}" ]]; then
      echo "#!weggefallen-${TIMESTAMP} ${key}=${old_values[$key]}" >> "$tmp"
    fi
  done

  # Check if there are actual changes
  if diff -q "$env_file" "$tmp" > /dev/null 2>&1; then
    rm -f "$tmp"
    return 0
  fi

  if $DRY_RUN; then
    echo "[DRY-RUN] Would update ${stack_name}/.env:"
    diff "$env_file" "$tmp" || true
    rm -f "$tmp"
    CHANGES=1
    return 0
  fi

  # Backup existing .env
  local backup="${env_file}.bck.${TIMESTAMP}"
  mv "$env_file" "$backup"
  mv "$tmp" "$env_file"
  echo "Updated ${stack_name}/.env (backup: .env.bck.${TIMESTAMP})"
  CHANGES=1
}

# Process all stack directories
for dir in "$SCRIPT_DIR"/*/; do
  if [[ -d "$dir" ]]; then
    sync_stack "${dir%/}"
  fi
done

exit "$CHANGES"
