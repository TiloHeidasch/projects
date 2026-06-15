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

  # Before up: capture current container start times
  OLD_TIMES=""
  if [ -d "$dir" ]; then
    OLD_TIMES=$(docker compose -f "$dir/compose.yaml" -f "$dir/compose.override.yaml" ps -q 2>/dev/null | xargs -r docker inspect --format='{{.State.StartedAt}}' 2>/dev/null | sort)
  fi

  docker compose -f "$dir/compose.yaml" -f "$dir/compose.override.yaml" up -d --pull always --build --remove-orphans

  if [ $? -eq 0 ]; then
    echo "✓ $project started successfully"

    # After up: capture new container start times
    NEW_TIMES=$(docker compose -f "$dir/compose.yaml" -f "$dir/compose.override.yaml" ps -q 2>/dev/null | xargs -r docker inspect --format='{{.State.StartedAt}}' 2>/dev/null | sort)

    # If containers changed or started_at doesn't exist, update it
    if [ "$OLD_TIMES" != "$NEW_TIMES" ] || [ ! -f "$dir/started_at" ]; then
      # Get the latest (most recent) container start time
      LATEST_START=$(echo "$NEW_TIMES" | tail -1)
      if [ -n "$LATEST_START" ]; then
        # Convert to ISO-8601 with timezone (e.g., 2026-05-15T18:28:06+02:00)
        FORMATTED=$(date -d "$LATEST_START" -Iseconds 2>/dev/null)
        if [ -n "$FORMATTED" ]; then
          echo "$FORMATTED" > "$dir/started_at"
        fi
      fi
    fi
  else
    echo "✗ $project failed to start"
  fi

  echo ""
done

echo "================================"
echo "All projects processed!"
