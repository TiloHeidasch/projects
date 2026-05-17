#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 2

for dir in "$SCRIPT_DIR"/*/; do
  project=$(basename "$dir")

  if [ ! -f "$dir/compose.yaml" ]; then
    echo "⚠ Skipping $project (no compose.yaml found)"
    continue
  fi

  echo "▶ Recreating $project..."
  docker compose -f "$dir/compose.yaml" -f "$dir/compose.override.yaml" up -d --force-recreate --remove-orphans

  if [ $? -eq 0 ]; then
    echo "✓ $project recreated"
  else
    echo "✗ $project failed"
  fi

  echo ""
done

echo "================================"
echo "All projects processed!"
