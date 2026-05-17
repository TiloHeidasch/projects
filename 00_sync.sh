#!/bin/bash

echo "Syncing compose projects from Git..."
echo "===================================="
echo ""

cd "$(dirname "$0")"

# Git is the single source of truth - discard all local changes
git fetch origin main

if [ $? -ne 0 ]; then
  echo ""
  echo "✗ Fetch failed. Please check your Git configuration."
  exit 1
fi

git reset --hard origin/main

if [ $? -eq 0 ]; then
  echo ""
  echo "✓ Sync completed successfully!"
  echo "  Local changes have been overwritten with remote state."
else
  echo ""
  echo "✗ Reset failed. Please check your Git configuration."
  exit 1
fi
