# SortAI Project - Claude AI Context

## Custom SQLite Build

This project requires a custom SQLite build with snapshot functions enabled for GRDB compatibility.

### Location
```
.local/sqlite/install/
├── libsqlite3.dylib    # Custom-built SQLite library
├── sqlite3.h           # SQLite header
└── sqlite3ext.h        # SQLite extension header
```

### Build Configuration
The custom SQLite is built with these flags enabled:
- `SQLITE_ENABLE_SNAPSHOT=1` - **Required for GRDB**
- `SQLITE_ENABLE_COLUMN_METADATA=1`
- `SQLITE_ENABLE_FTS5=1`
- `SQLITE_ENABLE_JSON1=1`
- `SQLITE_ENABLE_RTREE=1`
- `SQLITE_THREADSAFE=1`

### Rebuilding (if needed)
```bash
cd .local/sqlite/sqlite-amalgamation-3470200
./build_sqlite.sh
```

### Building the Project

#### Command Line (Swift Package Manager)
```bash
# Use the custom SQLite from .local
swift build \
  -Xcc -I$(pwd)/.local/sqlite/install \
  -Xlinker -L$(pwd)/.local/sqlite/install \
  -Xlinker -rpath -Xlinker $(pwd)/.local/sqlite/install
```

Or use the provided script:
```bash
./build.sh
```

#### Running Tests
The test runner needs the sqlite library copied to the build output directory:
```bash
# Copy custom SQLite to build directory first
cp .local/sqlite/install/libsqlite3.dylib .build/arm64-apple-macosx/debug/

# Then run tests
swift test \
  -Xcc -I$(pwd)/.local/sqlite/install \
  -Xlinker -L$(pwd)/.local/sqlite/install

# Or run a specific test suite
swift test --filter "NGramEmbeddingTests" \
  -Xcc -I$(pwd)/.local/sqlite/install \
  -Xlinker -L$(pwd)/.local/sqlite/install
```

#### Xcode
For Xcode builds, the `copy_sqlite_for_xcode.sh` script copies the library to the DerivedData directory. See `XCODE_BUILD_GUIDE.md` for details.

### Why Custom SQLite?
The system SQLite and Homebrew SQLite (`/opt/homebrew/opt/sqlite`) do **not** include the `sqlite3_snapshot_*` functions that GRDB uses for database snapshots. This causes linker errors like:
```
Symbol not found: _sqlite3_snapshot_cmp
```

The custom build in `.local/sqlite/install/` has `SQLITE_ENABLE_SNAPSHOT=1` enabled, which provides these required symbols.

---

## Project Structure Quick Reference

### Key Directories
- `Sources/SortAI/Core/` - Core logic (Brain, LLM, Persistence, etc.)
- `Sources/SortAI/App/` - SwiftUI application and views
- `Tests/SortAITests/` - Unit tests
- `Tests/Fixtures/TestFiles/` - Test data files

### Specification Documents
- `spec.md` - Main product specification
- `SortAIv1_1.md` - v1.1 implementation plan and phases

### Configuration
- `Package.swift` - Swift package definition
- `build.sh` - Build script with custom SQLite flags

