#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 2

declare -A results=()

run_step() {
  local name="$1"
  local script="$2"
  if bash "$script"; then
    results["$name"]="OK"
  else
    results["$name"]="FAILED"
  fi
}

echo "=== Running 00_sync.sh ==="
run_step "00_sync" "00_sync.sh"
echo ""

echo "=== Running 02_sync-env.sh ==="
run_step "02_sync-env" "02_sync-env.sh"
echo ""

echo "=== Running 10_start-all.sh ==="
run_step "10_start-all" "10_start-all.sh"
echo ""

echo "================================"
echo "=== Summary ==="
for step in "00_sync" "02_sync-env" "10_start-all"; do
  printf "%-20s %s\n" "$step:" "${results[$step]}"
done

for status in "${results[@]}"; do
  [[ "$status" == "FAILED" ]] && exit 1
done
exit 0
