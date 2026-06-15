#!/bin/bash
# Clones or pulls the Odysseus source into ./build-src/ for Docker build.
# Run this before 99_all.sh when Odysseus updates are available.
#
# Usage:
#   bash projects/odysseus/build.sh

set -euo pipefail

cd "$(dirname "$0")"

SRC_DIR="./build-src"
REPO_URL="https://github.com/pewdiepie-archdaemon/odysseus.git"
BRANCH="main"

echo "=== Odysseus build-src sync ==="
echo "Repo:   $REPO_URL"
echo "Branch: $BRANCH"
echo "Target: $SRC_DIR"
echo ""

if [ -d "$SRC_DIR" ]; then
  echo "→ Updating existing clone..."
  cd "$SRC_DIR"
  git checkout "$BRANCH"
  git pull
  echo "✓ Updated to $(git rev-parse --short HEAD)"
else
  echo "→ Cloning repository..."
  git clone -b "$BRANCH" "$REPO_URL" "$SRC_DIR"
  echo "✓ Cloned to $(cd "$SRC_DIR" && git rev-parse --short HEAD)"
fi

echo ""
echo "=== Done ==="
echo "Run 99_all.sh to build and start Odysseus."
