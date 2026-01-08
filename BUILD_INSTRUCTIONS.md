# SortAI Build Instructions

## Overview

SortAI uses a custom-built SQLite library with snapshot support enabled to satisfy GRDB 6.29.0 requirements. This document explains how to build and test the project.

## Prerequisites

- macOS 15+ (Sequoia/Tahoe)
- Xcode 16+ with Swift 6.0+
- Command-line tools installed

## Quick Start

### Building the Project

```bash
./build.sh
```

This script:
1. Verifies the custom SQLite library exists
2. Cleans previous build artifacts
3. Builds SortAI with proper SQLite flags
4. Creates the executable at `.build/debug/SortAI`

### Running Tests

```bash
# Copy the SQLite library to the test bundle location
cp .local/sqlite/install/libsqlite3.dylib .build/arm64-apple-macosx/debug/

# Run tests
swift test
```

All 106 tests should pass.

## Custom SQLite Library

### Why Custom SQLite?

GRDB 6.29.0 requires SQLite snapshot functions (`sqlite3_snapshot_*`) that are not available in:
- macOS system SQLite (stripped-down headers for App Store compliance)
- Homebrew SQLite (snapshot support not enabled by default)

### Building Custom SQLite

The custom SQLite is already built and located at `.local/sqlite/install/`. If you need to rebuild it:

```bash
cd .local/sqlite/sqlite-amalgamation-3470200
./build_sqlite.sh
```

This compiles SQLite 3.47.2 with:
- `SQLITE_ENABLE_SNAPSHOT=1` - WAL snapshot support for GRDB
- `SQLITE_ENABLE_COLUMN_METADATA=1` - Column metadata queries
- `SQLITE_ENABLE_FTS5=1` - Full-text search
- `SQLITE_ENABLE_JSON1=1` - JSON functions
- `SQLITE_ENABLE_RTREE=1` - Spatial indexing
- `SQLITE_THREADSAFE=1` - Thread-safe operations

### Library Location

- **Source**: `.local/sqlite/sqlite-amalgamation-3470200/`
- **Headers**: `.local/sqlite/install/sqlite3.h`, `sqlite3ext.h`
- **Library**: `.local/sqlite/install/libsqlite3.dylib`

## Package Configuration

The `Package.swift` includes custom build settings:

```swift
.executableTarget(
    name: "SortAI",
    dependencies: [
        .product(name: "GRDB", package: "GRDB.swift")
    ],
    path: "Sources/SortAI",
    swiftSettings: [
        .unsafeFlags(["-Xcc", "-I.local/sqlite/install"])
    ],
    linkerSettings: [
        .unsafeFlags(["-L.local/sqlite/install", 
                     "-Xlinker", "-rpath", 
                     "-Xlinker", "@executable_path/../../.local/sqlite/install"])
    ]
)
```

## Troubleshooting

### Build Fails with "Custom SQLite not found"

Run the SQLite build script:
```bash
cd .local/sqlite/sqlite-amalgamation-3470200
./build_sqlite.sh
```

### Tests Fail with "Library not loaded: @rpath/libsqlite3.dylib"

Copy the library to the test bundle:
```bash
cp .local/sqlite/install/libsqlite3.dylib .build/arm64-apple-macosx/debug/
```

### Linker Warnings about macOS Version

The warning `building for macOS-15.0, but linking with dylib which was built for newer version 26.0` is harmless. The library works correctly despite the version mismatch in the metadata.

## Development Workflow

1. Make code changes
2. Run `./build.sh` to build
3. Copy SQLite library for tests: `cp .local/sqlite/install/libsqlite3.dylib .build/arm64-apple-macosx/debug/`
4. Run `swift test` to verify
5. Commit changes

## Distribution

When distributing SortAI, include:
- The compiled executable from `.build/debug/SortAI` or `.build/release/SortAI`
- The custom SQLite library from `.local/sqlite/install/libsqlite3.dylib`
- Ensure the library is in the same directory as the executable or in a location specified by the rpath

## Additional Notes

- The custom SQLite library is **required** - the project will not build with system or Homebrew SQLite
- The `build.sh` script is the recommended way to build the project
- For release builds, use `./build.sh -c release`
- The SQLite source and build scripts are included in the repository for reproducibility

