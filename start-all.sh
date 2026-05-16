#!/bin/bash

PROJECTS_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Starting all compose projects..."
echo "================================"
echo ""

for dir in "$PROJECTS_DIR"/*/; do
  project=$(basename "$dir")

  if [ ! -f "$dir/compose.yaml" ]; then
    echo "⚠ Skipping $project (no compose.yaml found)"
    continue
  fi

  echo "▶ Starting $project..."
  docker compose -f "$dir/compose.yaml" -f "$dir/compose.override.yaml" up -d --pull always --remove-orphans

  if [ $? -eq 0 ]; then
    echo "✓ $project started successfully"
  else
    echo "✗ $project failed to start"
  fi

  echo ""
done

echo "================================"
echo "All projects processed!"
