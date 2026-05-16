#!/bin/bash

echo "Syncing compose projects from Git..."
echo "===================================="
echo ""

cd "$(dirname "$0")"

git pull origin main

if [ $? -eq 0 ]; then
  echo ""
  echo "✓ Sync completed successfully!"
else
  echo ""
  echo "✗ Sync failed. Please check your Git configuration."
  exit 1
fi
