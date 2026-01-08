# Building SortAI in Xcode

This guide explains how to build and run SortAI in Xcode, including handling the custom SQLite library.

## Quick Start

### 1. Open Project in Xcode

```bash
cd path/to/osx_cleanup_llm
open Package.swift
```

### 2. Build Custom SQLite (First Time Only)

Before building in Xcode, build the custom SQLite library:

```bash
./build.sh
```

This creates the custom SQLite library at `.local/sqlite/install/libsqlite3.dylib`

### 3. Copy SQLite Library for Xcode

**Run this script after:**
- First build
- Cleaning build folder (Cmd+Shift+K)
- Changing schemes

```bash
./copy_sqlite_for_xcode.sh
```

### 4. Build and Run in Xcode

- **Build**: Cmd+B
- **Run**: Cmd+R
- **Test**: Cmd+U

## Why Custom SQLite?

SortAI requires SQLite with the `SQLITE_ENABLE_SNAPSHOT` feature enabled for GRDB snapshots. The system SQLite on macOS doesn't have this feature enabled, so we build a custom version.

## Troubleshooting

### Error: "Library not loaded: @rpath/libsqlite3.dylib"

This means the custom SQLite library isn't in the Xcode build directory.

**Solution:**
```bash
./copy_sqlite_for_xcode.sh
```

### Error: "Custom SQLite library not found"

You need to build the custom SQLite first:

```bash
./build.sh
```

### Clean Build Issues

If you clean the build folder in Xcode (Cmd+Shift+K), you'll need to run the copy script again:

```bash
./copy_sqlite_for_xcode.sh
```

## Alternative: Use Terminal Build Script

For a simpler workflow without Xcode-specific setup:

```bash
# Build
./build.sh

# Run
.build/debug/SortAI

# Test
./test.sh
```

This automatically handles the SQLite library paths.

## Automated Solution (Optional)

You can add a Run Script build phase in Xcode to automatically copy the library:

1. In Xcode, select your target
2. Go to **Build Phases**
3. Click **+** and select **New Run Script Phase**
4. Add this script:

```bash
#!/bin/bash
SQLITE_LIB="${SOURCE_ROOT}/.local/sqlite/install/libsqlite3.dylib"

if [ -f "$SQLITE_LIB" ]; then
    echo "Copying custom SQLite library..."
    cp "$SQLITE_LIB" "${BUILT_PRODUCTS_DIR}/"
    install_name_tool -id "@rpath/libsqlite3.dylib" "${BUILT_PRODUCTS_DIR}/libsqlite3.dylib"
    echo "✅ Custom SQLite library copied"
else
    echo "⚠️  Custom SQLite not found. Run ./build.sh first"
fi
```

5. Move this phase **before** "Compile Sources"

## Development Workflow

### Recommended: Terminal Build

```bash
# Build and test
./build.sh && ./test.sh

# Run
.build/debug/SortAI
```

### If Using Xcode

```bash
# First time setup
./build.sh
./copy_sqlite_for_xcode.sh

# Then in Xcode:
# - Open Package.swift
# - Build (Cmd+B)
# - Run (Cmd+R)

# After clean builds:
./copy_sqlite_for_xcode.sh
```

## CI/CD

For automated builds, use the terminal build script:

```yaml
# .github/workflows/test.yml
- name: Build
  run: ./build.sh
  
- name: Test
  run: ./test.sh
```

## File Locations

| Item | Location |
|------|----------|
| Custom SQLite | `.local/sqlite/install/libsqlite3.dylib` |
| Build Script | `build.sh` |
| Test Script | `test.sh` |
| Copy Script | `copy_sqlite_for_xcode.sh` |
| Xcode Builds | `~/Library/Developer/Xcode/DerivedData/osx_cleanup_llm-*/Build/Products/` |

## Summary

**Simplest Workflow:**
```bash
./build.sh && .build/debug/SortAI
```

**Xcode Workflow:**
```bash
./build.sh                    # Once
./copy_sqlite_for_xcode.sh    # After clean builds
# Then use Xcode normally
```

---

**Questions?** Check `README.md` or the build scripts for more details.

