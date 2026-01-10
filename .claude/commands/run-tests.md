---
description: "Run tests with proper SQLite configuration"
argument-hint: "[optional: test filter]"
allowed-tools: ["Bash"]
---

# Run Tests

Ensure custom SQLite is available and run tests.

1. Copy SQLite library if needed:
   ```bash
   mkdir -p .build/arm64-apple-macosx/debug
   cp .local/sqlite/install/libsqlite3.dylib .build/arm64-apple-macosx/debug/ 2>/dev/null || echo "Library already in place"
   ```

2. Run tests:
   If $ARGUMENTS is provided, filter by that test name:
   ```bash
   swift test --filter "$ARGUMENTS" -Xcc -I$(pwd)/.local/sqlite/install -Xlinker -L$(pwd)/.local/sqlite/install
   ```
   
   Otherwise run all tests:
   ```bash
   swift test -Xcc -I$(pwd)/.local/sqlite/install -Xlinker -L$(pwd)/.local/sqlite/install
   ```

Report test results summary.

