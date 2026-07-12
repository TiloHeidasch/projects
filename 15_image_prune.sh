#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 2

echo "=== Pruning dangling Docker images ==="
docker image prune -f
echo "Done."
