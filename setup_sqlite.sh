#!/bin/bash
# Setup script for custom SQLite with SQLITE_ENABLE_SNAPSHOT
# This is required for GRDB snapshot support

set -e

SQLITE_VERSION="3470200"
SQLITE_URL="https://sqlite.org/2024/sqlite-amalgamation-${SQLITE_VERSION}.zip"
LOCAL_DIR=".local/sqlite"
SQLITE_DIR="${LOCAL_DIR}/sqlite-amalgamation-${SQLITE_VERSION}"
INSTALL_DIR="${LOCAL_DIR}/install"

echo "=== SortAI SQLite Setup ==="
echo ""

# Create directories
mkdir -p "$LOCAL_DIR"

# Check if already set up
if [ -f "$INSTALL_DIR/libsqlite3.dylib" ]; then
    echo "✅ Custom SQLite already installed at $INSTALL_DIR"
    echo ""
    echo "To rebuild, run:"
    echo "  rm -rf $INSTALL_DIR && ./setup_sqlite.sh"
    exit 0
fi

# Download if needed
if [ ! -d "$SQLITE_DIR" ]; then
    echo "📥 Downloading SQLite amalgamation..."
    cd "$LOCAL_DIR"
    curl -L -o "sqlite-amalgamation-${SQLITE_VERSION}.zip" "$SQLITE_URL"
    unzip -o "sqlite-amalgamation-${SQLITE_VERSION}.zip"
    cd - > /dev/null
    echo "✅ Downloaded and extracted"
else
    echo "✅ SQLite source already exists"
fi

# Create build script if it doesn't exist
BUILD_SCRIPT="${SQLITE_DIR}/build_sqlite.sh"
if [ ! -f "$BUILD_SCRIPT" ]; then
    echo "📝 Creating build script..."
    cat > "$BUILD_SCRIPT" << 'BUILDSCRIPT'
#!/bin/bash
# Build SQLite with SQLITE_ENABLE_SNAPSHOT for GRDB

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")/install"

echo "Building SQLite with snapshot support..."
echo "Install directory: $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"

# Compile with snapshot support enabled
cd "$SCRIPT_DIR"
clang -dynamiclib \
    -DSQLITE_ENABLE_SNAPSHOT=1 \
    -DSQLITE_ENABLE_FTS5 \
    -DSQLITE_ENABLE_JSON1 \
    -DSQLITE_ENABLE_RTREE \
    -DSQLITE_ENABLE_COLUMN_METADATA \
    -DSQLITE_MAX_VARIABLE_NUMBER=250000 \
    -O2 \
    -o "$INSTALL_DIR/libsqlite3.dylib" \
    sqlite3.c

# Copy header
cp sqlite3.h "$INSTALL_DIR/"

# Set install name
install_name_tool -id "@rpath/libsqlite3.dylib" "$INSTALL_DIR/libsqlite3.dylib"

echo ""
echo "✅ SQLite built successfully!"
echo "Library: $INSTALL_DIR/libsqlite3.dylib"
BUILDSCRIPT
    chmod +x "$BUILD_SCRIPT"
fi

# Build
echo "🔨 Building SQLite..."
cd "$SQLITE_DIR"
./build_sqlite.sh
cd - > /dev/null

echo ""
echo "=== Setup Complete ==="
echo ""
echo "You can now build SortAI:"
echo "  ./build.sh"
echo ""
echo "Or for Xcode:"
echo "  ./build.sh && ./copy_sqlite_for_xcode.sh"

