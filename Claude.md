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

---

## Git Workflow & AI Development

See `GitWorkflow.md` for the complete workflow documentation.

### Quick Commands
```bash
/new-feature <name>    # Start feature branch
/new-bugfix <name>     # Start bugfix branch
/new-proto <name>      # Start prototype branch
/pr-ready              # Check if ready for PR
/create-pr             # Create pull request
/sync-main             # Rebase on main
/ship-it               # Merge and cleanup
/run-tests [filter]    # Run tests
```

### Ralph Loop for Complex Tasks
```bash
/ralph-loop "task description" --max-iterations 20 --completion-promise "DONE"
/cancel-ralph          # Cancel active loop
```

### CI/CD
- GitHub Actions runs on all PRs (`.github/workflows/ci.yml`)
- Claude reviews all PRs (`.github/workflows/claude-review.yml`)
- Requires `ANTHROPIC_API_KEY` secret in repository settings

---

## Workflow Issues & Resolutions

*Document issues encountered during development and their solutions here for continuous improvement.*

### Template

```markdown
## Issue: [Brief Title]

**Date**: YYYY-MM-DD
**Branch**: feature/xxx

**Problem**: 
[What went wrong]

**Root Cause**:
[Why it happened]

**Solution**:
[How it was fixed]

**Prevention**:
[Changes to prevent recurrence]
```

---

## Known Gotchas

### 1. SQLite Library Not Found at Runtime
**Symptom**: `dyld: Library not loaded: @rpath/libsqlite3.dylib`

**Fix**: 
```bash
cp .local/sqlite/install/libsqlite3.dylib .build/arm64-apple-macosx/debug/
```

### 2. Tests Fail with Snapshot Symbol Errors
**Symptom**: `Symbol not found: _sqlite3_snapshot_cmp`

**Fix**: Ensure using custom SQLite, not system SQLite. Check linker flags in test command.

### 3. GitHub Actions SQLite Cache Miss
**Symptom**: CI builds SQLite every time

**Fix**: Check cache key matches architecture. The CI workflow caches by `runner.os` and `runner.arch`.

