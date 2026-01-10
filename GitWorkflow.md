# SortAI Git Workflow & AI-Assisted Development

This document establishes the Git workflow, PR process, and AI-assisted development practices for SortAI. It integrates GitHub Flow, Claude Code with ralph-wiggum, GitHub Actions CI/CD, and memory-based continuous improvement.

---

## Table of Contents

1. [Branching Strategy: GitHub Flow](#branching-strategy-github-flow)
2. [Branch Naming Conventions](#branch-naming-conventions)
3. [Development Workflow](#development-workflow)
4. [Ralph-Wiggum for Iterative Development](#ralph-wiggum-for-iterative-development)
5. [Custom Slash Commands](#custom-slash-commands)
6. [GitHub Actions CI/CD](#github-actions-cicd)
7. [AI-Powered PR Reviews](#ai-powered-pr-reviews)
8. [MCP Server Integration](#mcp-server-integration)
9. [Memory-Based Continuous Improvement](#memory-based-continuous-improvement)
10. [Issue Resolution Protocol](#issue-resolution-protocol)
11. [Quick Reference](#quick-reference)

---

## Branching Strategy: GitHub Flow

SortAI uses **GitHub Flow** - a lightweight, branch-based workflow optimized for solo development with continuous delivery.

### Core Principles

```
main ─────●─────●─────●─────●─────●──────► (always deployable)
           \         /       \   /
            ●───────●         ●─● 
          feature/x        bugfix/y
```

- **`main`** branch is always production-ready
- Short-lived feature branches for all work
- No `develop` branch - merge directly to `main`
- PRs required for all changes (enables AI review)

### Branch Lifecycle

1. **Create** branch from `main`
2. **Develop** with frequent commits
3. **Push** to origin
4. **Open PR** for AI review
5. **Merge** after approval
6. **Delete** branch after merge

---

## Branch Naming Conventions

| Type | Pattern | Example |
|------|---------|---------|
| Features | `feature/<short-description>` | `feature/ollama-streaming` |
| Bug Fixes | `bugfix/<issue-or-description>` | `bugfix/embedding-cache-leak` |
| Hotfixes | `hotfix/<critical-issue>` | `hotfix/db-migration-crash` |
| Prototypes | `proto/<experiment-name>` | `proto/apple-intelligence-api` |
| Exploration | `explore/<technology>` | `explore/whisper-transcription` |
| Refactors | `refactor/<area>` | `refactor/llm-provider-layer` |

### Naming Rules

- Use lowercase and hyphens (no underscores or spaces)
- Keep descriptions concise but descriptive
- Include issue number if applicable: `bugfix/42-taxonomy-crash`

---

## Development Workflow

### Starting New Work

```bash
# Ensure you're on latest main
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/my-new-feature

# Start development...
```

### During Development

```bash
# Stage and commit frequently with descriptive messages
git add -A
git commit -m "feat: implement Ollama streaming response handler

- Add StreamingLLMProvider protocol
- Implement async iterator for token chunks  
- Update OpenAIProvider for compatibility"

# Push to remote (first push)
git push -u origin feature/my-new-feature

# Subsequent pushes
git push
```

### Commit Message Format

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat:` New feature
- `fix:` Bug fix
- `refactor:` Code refactoring
- `docs:` Documentation
- `test:` Adding/updating tests
- `chore:` Maintenance tasks
- `perf:` Performance improvements

### Opening a Pull Request

```bash
# Ensure your branch is up to date
git fetch origin
git rebase origin/main

# Push and create PR
git push
gh pr create --title "feat: Add Ollama streaming support" \
  --body "## Summary
  Implements streaming token response for Ollama provider.
  
  ## Changes
  - StreamingLLMProvider protocol
  - Ollama streaming implementation
  - Unit tests
  
  ## Testing
  - [x] Unit tests pass
  - [x] Manual testing with Ollama" \
  --assignee @me
```

### After PR Approval

```bash
# Merge via GitHub CLI
gh pr merge --squash --delete-branch

# Or merge via GitHub UI, then cleanup local
git checkout main
git pull
git branch -d feature/my-new-feature
```

---

## Ralph-Wiggum for Iterative Development

The [ralph-wiggum plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum) enables autonomous, iterative AI development loops. Perfect for well-defined tasks with clear completion criteria.

### When to Use Ralph

✅ **Good for:**
- Implementing features with clear requirements
- Getting tests to pass
- Refactoring with defined goals
- Greenfield implementations
- Bug fixes with reproducible test cases

❌ **Not good for:**
- Design decisions requiring human judgment
- Exploratory debugging
- One-shot operations
- Tasks with unclear success criteria

### Basic Usage

```bash
# Start a Ralph loop
/ralph-loop "Implement the EmbeddingCache layer with the following requirements:
- LRU eviction with 1000 entry limit
- Thread-safe access
- Persistence to SQLite on eviction
- Unit tests with >80% coverage

Output <promise>COMPLETE</promise> when all tests pass." \
--completion-promise "COMPLETE" \
--max-iterations 20
```

### Prompt Writing Best Practices

#### 1. Clear Completion Criteria

```markdown
# ❌ Bad
"Make the taxonomy classifier better"

# ✅ Good
"Improve taxonomy classifier accuracy:
1. Add confidence scoring (0.0-1.0)
2. Implement fallback hierarchy
3. Tests verify >85% accuracy on test set
4. Update TaxonomyInferenceEngine.swift

Output <promise>DONE</promise> when all tests pass."
```

#### 2. Incremental Phases

```markdown
"Implement Ollama provider in phases:

Phase 1: Basic request/response
- OllamaProvider struct
- Simple generate() method
- Unit tests

Phase 2: Streaming support  
- Add stream() method
- Async token iterator
- Integration test

Phase 3: Error handling
- Retry logic
- Graceful degradation
- Edge case tests

Output <promise>PHASES COMPLETE</promise> when all phases done."
```

#### 3. Self-Correction Loop

```markdown
"Implement feature X using TDD:
1. Write failing test for next requirement
2. Implement minimal code to pass
3. Run: swift test --filter FeatureXTests
4. If tests fail, analyze output and fix
5. Refactor if needed
6. Repeat until all requirements met

Requirements:
- [list requirements here]

Output <promise>ALL TESTS GREEN</promise> when complete."
```

#### 4. Escape Hatches

Always use `--max-iterations` as a safety net:

```bash
# Recommended: Set reasonable limits
/ralph-loop "Try to implement X" --max-iterations 15

# In prompt, handle stuck scenarios:
"After 10 iterations without progress:
- Document blocking issues in BLOCKED.md
- List attempted approaches  
- Suggest alternatives for human review"
```

### Canceling a Loop

```bash
/cancel-ralph
```

---

## Custom Slash Commands

Create custom commands in `.claude/commands/` to streamline the workflow.

### `/new-feature` - Start Feature Development

Create `.claude/commands/new-feature.md`:

```markdown
---
description: "Start a new feature branch with proper setup"
argument-hint: "<feature-name>"
allowed-tools: ["Bash"]
---

# New Feature Setup

Execute these steps:

1. Ensure clean working directory:
   ```bash
   git status --porcelain
   ```

2. Update main and create branch:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feature/$ARGUMENTS
   ```

3. Confirm:
   "Created feature branch: feature/$ARGUMENTS. Ready for development."
```

### `/new-bugfix` - Start Bugfix

Create `.claude/commands/new-bugfix.md`:

```markdown
---
description: "Start a bugfix branch"
argument-hint: "<issue-number-or-description>"
---

Execute:
```bash
git checkout main && git pull origin main
git checkout -b bugfix/$ARGUMENTS
```

Ready to fix the bug. Describe the issue for analysis.
```

### `/pr-ready` - Prepare for PR

Create `.claude/commands/pr-ready.md`:

```markdown
---
description: "Prepare current branch for PR submission"
allowed-tools: ["Bash", "Read"]
---

# PR Preparation Checklist

1. Run tests:
   ```bash
   ./build.sh && swift test -Xcc -I$(pwd)/.local/sqlite/install -Xlinker -L$(pwd)/.local/sqlite/install
   ```

2. Check for uncommitted changes:
   ```bash
   git status
   ```

3. Ensure branch is rebased on main:
   ```bash
   git fetch origin && git log --oneline origin/main..HEAD
   ```

4. Generate PR description based on commits:
   ```bash
   git log --oneline origin/main..HEAD
   ```

Summarize changes and suggest PR title/description.
```

### `/sync-main` - Sync with Main

Create `.claude/commands/sync-main.md`:

```markdown
---
description: "Sync current branch with latest main"
---

```bash
git fetch origin
git rebase origin/main
```

If conflicts occur, help resolve them.
```

### `/ship-it` - Merge and Cleanup

Create `.claude/commands/ship-it.md`:

```markdown
---
description: "Merge approved PR and cleanup branch"
---

```bash
gh pr merge --squash --delete-branch
git checkout main
git pull origin main
```
```

---

## GitHub Actions CI/CD

### Swift Build & Test Workflow

Create `.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: macos-14  # Apple Silicon runner
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Setup Swift
        uses: swift-actions/setup-swift@v2
        with:
          swift-version: '6.0'
      
      - name: Cache SQLite Build
        id: cache-sqlite
        uses: actions/cache@v4
        with:
          path: .local/sqlite/install
          key: sqlite-snapshot-3470200-${{ runner.os }}
      
      - name: Build Custom SQLite
        if: steps.cache-sqlite.outputs.cache-hit != 'true'
        run: |
          mkdir -p .local/sqlite
          cd .local/sqlite
          curl -O https://www.sqlite.org/2024/sqlite-amalgamation-3470200.zip
          unzip sqlite-amalgamation-3470200.zip
          cd sqlite-amalgamation-3470200
          ./build_sqlite.sh
      
      - name: Build SortAI
        run: |
          swift build \
            -Xcc -I$(pwd)/.local/sqlite/install \
            -Xlinker -L$(pwd)/.local/sqlite/install \
            -Xlinker -rpath \
            -Xlinker $(pwd)/.local/sqlite/install
      
      - name: Copy SQLite for Tests
        run: |
          mkdir -p .build/arm64-apple-macosx/debug
          cp .local/sqlite/install/libsqlite3.dylib .build/arm64-apple-macosx/debug/
      
      - name: Run Tests
        run: |
          swift test \
            -Xcc -I$(pwd)/.local/sqlite/install \
            -Xlinker -L$(pwd)/.local/sqlite/install

  lint:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: SwiftLint
        run: |
          brew install swiftlint || true
          swiftlint lint --reporter github-actions-logging || true
```

### Claude AI PR Review Workflow

Create `.github/workflows/claude-review.yml`:

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, synchronize, reopened]

permissions:
  contents: read
  pull-requests: write
  issues: write

jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
      
      - name: Claude Code Review
        uses: anthropics/claude-code-action@beta
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          model: claude-sonnet-4-20250514
          prompt: |
            Review this pull request for a Swift/macOS application (SortAI).
            
            Focus on:
            1. **Swift Best Practices**: Modern Swift 6 patterns, actor isolation, Sendable conformance
            2. **Memory Safety**: Retain cycles, proper weak references, actor boundaries
            3. **Error Handling**: Proper error propagation, try/catch patterns
            4. **Thread Safety**: MainActor usage, async/await patterns
            5. **Architecture**: Consistency with existing patterns in the codebase
            6. **Tests**: Adequate test coverage for new functionality
            7. **Custom SQLite**: Ensure no system SQLite references leak in
            
            For context, this app uses:
            - GRDB with custom SQLite (snapshot functions required)
            - SwiftUI with macOS 15+ features
            - Multiple LLM providers (Ollama, OpenAI, Apple Intelligence)
            
            Provide specific, actionable feedback with code suggestions.
          include_files: "**/*.swift"
          exclude_files: ".build/**,Prototypes/**"
```

### Required Secrets

Add to repository Settings → Secrets → Actions:

| Secret | Description |
|--------|-------------|
| `ANTHROPIC_API_KEY` | Claude API key for PR reviews |

---

## AI-Powered PR Reviews

Claude is the default reviewer for all PRs. The review focuses on:

### Review Checklist

1. **Swift 6 Compliance**
   - Sendable conformance
   - Actor isolation boundaries
   - Strict concurrency checking

2. **Architecture Consistency**
   - Follows existing patterns
   - Proper separation of concerns
   - Protocol-oriented design

3. **Custom SQLite Compatibility**
   - No system SQLite imports
   - Proper linker flags maintained
   - Snapshot function usage

4. **LLM Provider Layer**
   - Provider protocol compliance
   - Graceful degradation
   - Error handling patterns

5. **Test Coverage**
   - New code has tests
   - Edge cases covered
   - Async test patterns

### Responding to Review Comments

When Claude leaves review comments:

1. Address each comment with a commit or reply
2. Use conventional commit messages for fixes
3. Request re-review after changes

```bash
# After addressing comments
git add -A
git commit -m "fix(review): address Claude review feedback

- Add missing Sendable conformance to Provider
- Fix retain cycle in async closure
- Add test for edge case"
git push
```

---

## MCP Server Integration

SortAI leverages multiple MCP servers for enhanced development:

### Available MCP Servers

| Server | Purpose | Usage |
|--------|---------|-------|
| **taskmaster-ai** | Task management | Break down features into subtasks |
| **openmemory** | Persistent memory | Remember project context across sessions |
| **xcodebuildmcp** | Xcode integration | Build, test, run from Claude |
| **GitHub** | GitHub integration | Create issues, PRs, view repos |

### Using TaskMaster for Complex Features

```bash
# Initialize tasks from a feature description
# Use the MCP taskmaster tools to break down work

# Example: Parse a feature into tasks
mcp_taskmaster-ai_parse_prd for feature planning
mcp_taskmaster-ai_expand_task for detailed subtasks
mcp_taskmaster-ai_set_task_status as you complete work
```

### Memory-Based Development

```bash
# Store important decisions
mcp_openmemory_add-memory "SortAI uses custom SQLite with SQLITE_ENABLE_SNAPSHOT=1"

# Search past decisions
mcp_openmemory_search-memories "SQLite configuration"
```

---

## Memory-Based Continuous Improvement

### Claude.md Updates

When encountering workflow issues, update `Claude.md` with:

1. **Problem Description**: What went wrong
2. **Root Cause**: Why it happened
3. **Solution**: How it was fixed
4. **Prevention**: How to avoid in future

### Template for Issue Documentation

Add to `Claude.md`:

```markdown
---

## Workflow Issue: [Brief Title]

**Date**: YYYY-MM-DD

**Problem**: 
[Description of what went wrong]

**Root Cause**:
[Analysis of why it happened]

**Solution**:
[How it was resolved]

**Prevention**:
[Changes to prevent recurrence]

**Related Files**:
- `path/to/file.swift`
```

### Automated Memory Updates

After resolving issues, Claude should:

1. Update `Claude.md` with the resolution
2. Add to openmemory for cross-session recall
3. Update this workflow doc if process changes needed

---

## Issue Resolution Protocol

When hitting issues during development:

### 1. Document Immediately

```bash
# Create an issue log entry
echo "## Issue: [Title]" >> ISSUES.md
echo "Date: $(date)" >> ISSUES.md
echo "Branch: $(git branch --show-current)" >> ISSUES.md
```

### 2. Search Memory

```bash
# Check if we've seen this before
mcp_openmemory_search-memories "[error message or symptom]"
```

### 3. Resolve and Document

After fixing:

1. Commit the fix
2. Update `Claude.md` if it's a project-wide issue
3. Add to memory if it's likely to recur
4. Update this workflow if process needs adjustment

### 4. Ralph Loop for Complex Fixes

For tricky bugs:

```bash
/ralph-loop "Fix the [specific issue]:

Current behavior: [what's happening]
Expected behavior: [what should happen]
Reproduction: [steps to reproduce]

Success criteria:
- Bug no longer occurs
- Regression test added
- No new failures

Output <promise>FIXED</promise> when tests pass." \
--completion-promise "FIXED" \
--max-iterations 15
```

---

## Quick Reference

### Daily Commands

```bash
# Start new work
/new-feature my-feature-name

# During development
git add -A && git commit -m "feat: description"

# Prepare for PR  
/pr-ready

# Create PR
gh pr create

# After approval
/ship-it
```

### Ralph Commands

```bash
# Start iteration loop
/ralph-loop "prompt" --max-iterations 20 --completion-promise "DONE"

# Cancel loop
/cancel-ralph

# Get help
/help
```

### Build Commands

```bash
# Build
./build.sh

# Build with app bundle
./build.sh --app

# Run tests
swift test -Xcc -I$(pwd)/.local/sqlite/install -Xlinker -L$(pwd)/.local/sqlite/install

# Run specific test
swift test --filter "TestName" -Xcc -I$(pwd)/.local/sqlite/install -Xlinker -L$(pwd)/.local/sqlite/install
```

### Git Commands

```bash
# Sync with main
git fetch origin && git rebase origin/main

# Interactive rebase for cleanup
git rebase -i origin/main

# Force push after rebase
git push --force-with-lease

# View PR status
gh pr status
```

---

## Recommended VS Code / Cursor Extensions

| Extension | Purpose |
|-----------|---------|
| **GitLens** | Enhanced git history and blame |
| **GitHub Pull Requests** | Manage PRs from editor |
| **Swift** | Swift language support |
| **GitHub Copilot** | AI completion (complements Claude) |

---

## Appendix: Setup Checklist

### Initial Repository Setup

- [ ] Create `.github/workflows/ci.yml`
- [ ] Create `.github/workflows/claude-review.yml`
- [ ] Add `ANTHROPIC_API_KEY` to repository secrets
- [ ] Create `.claude/commands/` directory
- [ ] Add custom slash commands
- [ ] Verify ralph-wiggum plugin is enabled
- [ ] Configure branch protection on `main`

### Branch Protection Settings

In GitHub → Settings → Branches → Add rule for `main`:

- [x] Require a pull request before merging
- [x] Require status checks to pass (CI workflow)
- [ ] Require branches to be up to date (optional for solo)
- [x] Include administrators

---

*Last updated: 2026-01-10*
*Maintained via Claude.md continuous improvement process*

