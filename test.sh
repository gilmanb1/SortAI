#!/bin/bash
# Test script for SortAI - handles SQLite library setup

set -e

SQLITE_LIB=".local/sqlite/install/libsqlite3.dylib"
BUILD_DIR=".build/arm64-apple-macosx/debug"

if [ ! -f "$SQLITE_LIB" ]; then
  echo "Error: Custom SQLite not found at $SQLITE_LIB"
  exit 1
fi

echo "Copying SQLite library to test bundle..."
mkdir -p "$BUILD_DIR"
cp "$SQLITE_LIB" "$BUILD_DIR/"

echo "Running tests..."
swift test "$@"

echo ""
echo "✅ Tests complete!"
