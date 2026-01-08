#!/bin/bash
# Copy custom SQLite library for Xcode builds

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SQLITE_LIB="$SCRIPT_DIR/.local/sqlite/install/libsqlite3.dylib"

# Check if custom SQLite exists
if [ ! -f "$SQLITE_LIB" ]; then
    echo "❌ Custom SQLite library not found at: $SQLITE_LIB"
    echo "Run './build.sh' first to build custom SQLite"
    exit 1
fi

# Find Xcode DerivedData directory for this project
DERIVED_DATA_BASE="$HOME/Library/Developer/Xcode/DerivedData"
PROJECT_NAME="osx_cleanup_llm"

# Find the project's DerivedData folder
DERIVED_DATA_DIR=$(find "$DERIVED_DATA_BASE" -maxdepth 1 -type d -name "${PROJECT_NAME}*" | head -1)

if [ -z "$DERIVED_DATA_DIR" ]; then
    echo "⚠️  Xcode DerivedData directory not found for $PROJECT_NAME"
    echo "Build the project in Xcode first, then run this script again"
    exit 1
fi

echo "📂 Found DerivedData: $DERIVED_DATA_DIR"

# Copy to Debug and Release build directories
for config in Debug Release; do
    TARGET_DIR="$DERIVED_DATA_DIR/Build/Products/$config"
    
    if [ -d "$TARGET_DIR" ]; then
        echo "📦 Copying libsqlite3.dylib to $config..."
        cp "$SQLITE_LIB" "$TARGET_DIR/"
        
        # Update install name
        install_name_tool -id "@rpath/libsqlite3.dylib" "$TARGET_DIR/libsqlite3.dylib"
        
        echo "✅ Copied to $config"
    else
        echo "⏭️  Skipping $config (directory doesn't exist yet)"
    fi
done

echo ""
echo "✅ Done! You can now run the app from Xcode"
echo ""
echo "💡 TIP: Run this script after cleaning build folder or changing schemes"

