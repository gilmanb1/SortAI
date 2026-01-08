#!/bin/bash
# Build script for SortAI using custom SQLite with snapshot support

set -e

# Configuration
SQLITE_DIR="$(pwd)/.local/sqlite/install"
APP_NAME="SortAI"
BUNDLE_ID="com.sortai.app"
VERSION="1.1.0"
BUILD_DIR=".build/debug"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Parse arguments
CREATE_APP_BUNDLE=false
EXTRA_ARGS=()

for arg in "$@"; do
  case $arg in
    --app)
      CREATE_APP_BUNDLE=true
      ;;
    --help|-h)
      echo "Usage: ./build.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --app      Create a macOS .app bundle (shows in Dock, menu bar works)"
      echo "  --help     Show this help message"
      echo ""
      echo "Examples:"
      echo "  ./build.sh              # Build executable only"
      echo "  ./build.sh --app        # Build and create .app bundle"
      echo "  ./build.sh -c release   # Build release configuration"
      exit 0
      ;;
    *)
      EXTRA_ARGS+=("$arg")
      ;;
  esac
done

# Verify custom SQLite exists
if [ ! -f "$SQLITE_DIR/libsqlite3.dylib" ]; then
  echo "Error: Custom SQLite not found. Run .local/sqlite/sqlite-amalgamation-3470200/build_sqlite.sh first"
  exit 1
fi

echo "Building SortAI with custom SQLite (snapshot support enabled)..."

# Clean build
rm -rf .build

# Build and link against our custom SQLite
swift build \
  -Xcc -I"$SQLITE_DIR" \
  -Xlinker -L"$SQLITE_DIR" \
  -Xlinker -rpath \
  -Xlinker "$SQLITE_DIR" \
  "${EXTRA_ARGS[@]}"

echo ""
echo "✅ Build complete!"
echo "Binary location: $BUILD_DIR/SortAI"
echo "SQLite library: $SQLITE_DIR/libsqlite3.dylib"

# Create .app bundle if requested
if [ "$CREATE_APP_BUNDLE" = true ]; then
  echo ""
  echo "Creating macOS .app bundle..."
  
  # Create bundle structure
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_BUNDLE/Contents/MacOS"
  mkdir -p "$APP_BUNDLE/Contents/Resources"
  mkdir -p "$APP_BUNDLE/Contents/Frameworks"
  
  # Copy executable
  cp "$BUILD_DIR/SortAI" "$APP_BUNDLE/Contents/MacOS/"
  
  # Copy custom SQLite library
  cp "$SQLITE_DIR/libsqlite3.dylib" "$APP_BUNDLE/Contents/Frameworks/"
  
  # Fix rpath to look in Frameworks
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/SortAI" 2>/dev/null || true
  
  # Create Info.plist
  cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

  # Create PkgInfo
  echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"
  
  # Create entitlements file for ad-hoc signing
  cat > "$APP_BUNDLE/Contents/entitlements.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOF

  # Create a simple app icon (SF Symbol-based placeholder)
  # For a real icon, replace this with an .icns file
  cat > "$APP_BUNDLE/Contents/Resources/AppIcon.icns.placeholder" << EOF
# Replace this with a real AppIcon.icns file
# You can create one from an image using:
# iconutil -c icns AppIcon.iconset
EOF

  # Ad-hoc sign the app bundle (required for modern macOS)
  echo "Signing app bundle..."
  codesign --force --deep --sign - \
    --entitlements "$APP_BUNDLE/Contents/entitlements.plist" \
    "$APP_BUNDLE" 2>/dev/null || {
    echo "⚠️  Ad-hoc signing failed (may still work without signing)"
  }

  echo ""
  echo "✅ App bundle created: $APP_BUNDLE"
  echo ""
  echo "To run the app:"
  echo "  open $APP_BUNDLE"
  echo ""
  echo "Or double-click SortAI.app in Finder at:"
  echo "  $(pwd)/$APP_BUNDLE"
  echo ""
  echo "Note: If the app doesn't launch, run directly:"
  echo "  .build/debug/SortAI"
fi
