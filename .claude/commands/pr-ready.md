---
description: "Prepare current branch for PR submission"
allowed-tools: ["Bash", "Read"]
---

# PR Preparation Checklist

Run through this checklist before opening a PR:

## 1. Build Check
```bash
./build.sh
```

## 2. Run Tests
```bash
cp .local/sqlite/install/libsqlite3.dylib .build/arm64-apple-macosx/debug/ 2>/dev/null || true
swift test -Xcc -I$(pwd)/.local/sqlite/install -Xlinker -L$(pwd)/.local/sqlite/install 2>&1 | tail -20
```

## 3. Check for Uncommitted Changes
```bash
git status --short
```

## 4. Ensure Rebased on Main
```bash
git fetch origin
git log --oneline origin/main..HEAD
```

## 5. Generate Commit Summary
```bash
git log --pretty=format:"- %s" origin/main..HEAD
```

Based on the results, provide:
1. Whether the branch is ready for PR
2. Any issues that need addressing
3. Suggested PR title and description based on commits

