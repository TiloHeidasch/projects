#!/bin/bash

echo "========================================"
echo "  Update & Start All Compose Projects"
echo "========================================"
echo ""

cd "$(dirname "$0")"

# Step 1: Sync from Git
echo "Step 1: Syncing from Git..."
echo "----------------------------------------"
bash sync.sh

if [ $? -ne 0 ]; then
  echo ""
  echo "✗ Sync failed. Aborting."
  exit 1
fi

echo ""
echo "Step 2: Starting all projects..."
echo "----------------------------------------"
bash start-all.sh

echo ""
echo "========================================"
echo "  Update & Start complete!"
echo "========================================"
