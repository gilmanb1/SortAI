# SortAI Git Workflow & AI-Assisted Development

This document establishes the Git workflow, PR process, and AI-assisted development practices for SortAI. It integrates GitHub Flow, Claude Code with ralph-wiggum, GitHub Actions CI/CD, and memory-based continuous improvement.

---

## Table of Contents

1. [Branching Strategy: GitHub Flow](#branching-strategy-github-flow)
2. [Branch Naming Conventions](#branch-naming-conventions)
3. [Development Workflow](#development-workflow)
4. [Hotfix Workflow](#hotfix-workflow)
5. [Prototype Branch Lifecycle](#prototype-branch-lifecycle)
6. [Testing Strategy](#testing-strategy)
7. [Database Migrations](#database-migrations)
8. [Ralph-Wiggum for Iterative Development](#ralph-wiggum-for-iterative-development)
9. [Custom Slash Commands](#custom-slash-commands)
10. [GitHub Actions CI/CD](#github-actions-cicd)
11. [AI-Powered PR Reviews](#ai-powered-pr-reviews)
12. [Auto-Merge Policy](#auto-merge-policy)
13. [Release & Distribution](#release--distribution)
14. [Changelog Management](#changelog-management)
15. [MCP Server Integration](#mcp-server-integration)
16. [Memory-Based Continuous Improvement](#memory-based-continuous-improvement)
17. [Issue Resolution Protocol](#issue-resolution-protocol)
18. [Rollback Procedures](#rollback-procedures)
19. [Quick Reference](#quick-reference)

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
- PRs required for features/bugfixes (enables AI review)
- **Hotfixes can go direct-to-main** when critical
- Force-pushing to feature branches is allowed

### Branch Lifecycle

1. **Create** branch from `main`
2. **Develop** with frequent commits
3. **Push** to origin (force-push after rebase is fine)
4. **Open PR** for AI review
5. **Auto-merge** after CI passes
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

### Handling Work-in-Progress

When you need to switch branches with uncommitted changes:

```bash
# Stash current work
git stash push -m "WIP: description of what you were doing"

# Switch branches and do other work...

# Later, restore your stash
git stash pop

# Or view all stashes
git stash list
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

# After rebasing, force-push is allowed
git push --force-with-lease
```

### Commit Message Format

Use [Conventional Commits](https://www.conventionalcommits.org/) for auto-changelog generation:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat:` New feature (triggers minor version bump)
- `fix:` Bug fix (triggers patch version bump)
- `refactor:` Code refactoring
- `docs:` Documentation
- `test:` Adding/updating tests
- `chore:` Maintenance tasks
- `perf:` Performance improvements
- `BREAKING CHANGE:` Breaking change (triggers major version bump)

### Opening a Pull Request

```bash
# Ensure your branch is up to date
git fetch origin
git rebase origin/main

# Push and create PR
git push --force-with-lease
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

### Draft PRs for Early Feedback

Open a draft PR when you want early feedback without triggering full review:

```bash
gh pr create --draft --title "WIP: Feature X"

# Convert to ready when complete
gh pr ready
```

### PR Size Guidelines

- **Target**: < 400 lines changed per PR
- **One concern per PR**: Don't mix refactoring with features
- **Split large features**: Use stacked PRs or feature flags
- **Exceptions**: Auto-generated code, large refactors with clear scope

### After PR Approval (Auto-Merged)

PRs auto-merge after CI passes. Clean up locally:

```bash
git checkout main
git pull
git branch -d feature/my-new-feature
```

---

## Hotfix Workflow

For critical issues, hotfixes can go **direct-to-main** without a PR:

```bash
# Start on main
git checkout main
git pull origin main

# Make the fix
# ... edit files ...

# Commit with hotfix type
git commit -m "fix(critical): resolve database corruption on launch

Refs #123"

# Push directly to main
git push origin main
```

**When to use hotfix:**
- Production is broken
- Data corruption risk
- Security vulnerability
- CI is down but fix is urgent

**After hotfix:**
1. Create a follow-up PR if tests need to be added
2. Document in Claude.md if it reveals a process gap

---

## Prototype Branch Lifecycle

Prototype branches (`proto/`) are for experimentation. They have a defined lifecycle:

### Creation

```bash
git checkout -b proto/new-experiment
```

### Experimentation Phase

- No PR required during experimentation
- Can push to origin for backup
- No code review needed

### Resolution (Choose One)

#### Option A: Graduate to Feature (Success)

If the prototype is successful and should be productized:

```bash
# Create a new feature branch from main
git checkout main
git pull
git checkout -b feature/productize-experiment

# Cherry-pick or port relevant changes from proto
git cherry-pick <commit-sha>  # or manually port code

# Create PR as normal
gh pr create
```

Document learnings in the PR description.

#### Option B: Archive with Learnings (Partial Success)

If some insights are valuable but the approach won't be used:

1. Create `docs/prototypes/experiment-name.md` documenting:
   - What was tried
   - What worked / didn't work
   - Key learnings
2. Delete the prototype branch

```bash
git push origin --delete proto/experiment
git branch -d proto/experiment
```

#### Option C: Abandon (Failure)

If the prototype proved the approach won't work:

1. Optionally document why it failed in Claude.md
2. Delete the branch

```bash
git push origin --delete proto/experiment
git branch -d proto/experiment
```

### Cleanup Policy

Prototype branches older than 30 days should be resolved (graduated, archived, or abandoned).

---

## Testing Strategy

SortAI has 31 test suites with ~12,000 lines of tests. They're categorized by execution speed:

### Fast Tests (Run Before Every Commit)

Pure unit tests with no I/O, mocks, or external dependencies. Run in < 5 seconds.

```bash
# Run fast tests locally
swift test --filter "CategoryPathTests|NGramEmbeddingTests|SphericalKMeansTests|CategoryBrowserTests" \
  -Xcc -I$(pwd)/.local/sqlite/install \
  -Xlinker -L$(pwd)/.local/sqlite/install
```

**Fast test suites:**
- `CategoryPathTests` - Path parsing logic
- `CategoryBrowserTests` - Browser navigation
- `NGramEmbeddingTests` - Text embedding math
- `SphericalKMeansTests` - Clustering algorithms
- `ConfigurationTests` - Config validation
- `DefaultsTests` - UserDefaults handling

### Medium Tests (Run Before Push)

Tests using in-memory database or light mocking. Run in < 30 seconds.

```bash
# Run medium tests
swift test --filter "PersistenceTests|EmbeddingCacheTests|PrototypeStoreTests|ConfidenceServiceTests" \
  -Xcc -I$(pwd)/.local/sqlite/install \
  -Xlinker -L$(pwd)/.local/sqlite/install
```

**Medium test suites:**
- `PersistenceTests` - Database operations (in-memory)
- `EmbeddingCacheTests` - Cache behavior
- `PrototypeStoreTests` - Prototype storage
- `ConfidenceServiceTests` - Confidence scoring
- `SafeFileOrganizerTests` - File operations (temp dirs)
- `FileLoggerTests` - Logging

### Slow Tests (Run in CI)

Integration tests, file system tests, or tests requiring network/APIs. Run in > 30 seconds.

```bash
# Run all tests (CI does this)
swift test -Xcc -I$(pwd)/.local/sqlite/install -Xlinker -L$(pwd)/.local/sqlite/install
```

**Slow test suites:**
- `FunctionalOrganizationTests` - End-to-end with real files
- `AppleIntelligenceTests` - Apple API integration
- `TaxonomyTests` - Full taxonomy pipeline
- `RuntimeWorkflowTests` - Complete workflows
- `DeepAnalyzerTests` - Deep analysis pipeline
- `OllamaModelManagerTests` - Ollama API calls

### Local Testing Workflow

```bash
# Before committing: fast tests
/run-tests CategoryPathTests

# Before pushing: fast + medium
/run-tests

# Full suite (or let CI do it)
swift test -Xcc -I$(pwd)/.local/sqlite/install -Xlinker -L$(pwd)/.local/sqlite/install
```

---

## Database Migrations

SortAI uses GRDB with SQLite. Schema changes require migrations.

### Creating a Migration

1. Add migration to `Sources/SortAI/Core/Persistence/Migrations/`
2. Follow the naming pattern: `Migration_YYYYMMDD_Description.swift`
3. Implement the `DatabaseMigrator` protocol

```swift
// Example: Sources/SortAI/Core/Persistence/Migrations/Migration_20260112_AddCacheTable.swift

import GRDB

struct Migration_20260112_AddCacheTable: DatabaseMigrator {
    static let identifier = "20260112_AddCacheTable"
    
    static func migrate(_ db: Database) throws {
        try db.create(table: "embedding_cache") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("hash", .text).notNull().unique()
            t.column("embedding", .blob).notNull()
            t.column("created_at", .datetime).notNull()
        }
    }
}
```

### Migration Testing Requirements

When adding a migration:

1. **Test migration on empty database** - New installs
2. **Test migration on populated database** - Existing users
3. **Test rollback if supported** - Optional but recommended

Add tests to `PersistenceTests.swift`:

```swift
func testMigration_AddCacheTable() throws {
    // Create database at previous version
    // Apply migration
    // Verify schema is correct
    // Verify existing data preserved
}
```

### PR Requirements for Migrations

When a PR includes migrations:

- [ ] Migration is idempotent (safe to run twice)
- [ ] Migration handles existing data gracefully
- [ ] Migration tested with populated database
- [ ] PR description documents schema changes
- [ ] Breaking changes noted in CHANGELOG

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

### Ralph Loop Logging

All Ralph loop sessions are logged to `ralph-loop-log.md` for later analysis:

```markdown
## Ralph Loop Session: 2026-01-12 14:30

**Task**: Implement EmbeddingCache layer
**Iterations**: 12 / 20
**Result**: SUCCESS (COMPLETE promise detected)

### Iteration Summary
1. Created EmbeddingCache struct - tests failed (missing LRU)
2. Added LRU eviction - tests failed (not thread-safe)
3. Added actor isolation - tests passed but coverage low
...
12. All requirements met, tests passing at 84% coverage

### Lessons Learned
- Actor isolation was the right approach for thread safety
- LRU with Dictionary + Array performed better than LinkedList
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

Custom commands in `.claude/commands/` streamline the workflow.

| Command | Description |
|---------|-------------|
| `/new-feature <name>` | Create feature branch from main |
| `/new-bugfix <name>` | Create bugfix branch from main |
| `/new-proto <name>` | Create prototype branch |
| `/pr-ready` | Run tests and prepare for PR |
| `/create-pr` | Create PR with generated description |
| `/sync-main` | Rebase current branch on main |
| `/ship-it` | Merge PR and cleanup |
| `/run-tests [filter]` | Run tests with SQLite flags |
| `/implement-feature` | Start Ralph loop for feature |

---

## GitHub Actions CI/CD

### Swift Build & Test Workflow

Located at `.github/workflows/ci.yml`:

- Runs on `macos-14` (Apple Silicon)
- Caches custom SQLite build
- Builds and runs all tests
- SwiftLint for code style

### Claude AI PR Review Workflow  

Located at `.github/workflows/claude-review.yml`:

- Triggers on PR open/update
- Claude reviews Swift code
- Focuses on Swift 6, concurrency, architecture
- Provides actionable feedback

### Required Secrets

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

6. **Database Migrations**
   - Migrations are safe
   - Existing data preserved
   - Breaking changes documented

---

## Auto-Merge Policy

For solo development, PRs **auto-merge** when:

1. ✅ CI passes (build + tests)
2. ✅ Claude review approves (no blocking issues)

### GitHub Actions Auto-Merge Configuration

Add to `.github/workflows/claude-review.yml`:

```yaml
- name: Enable Auto-merge
  if: github.actor == 'gilmanb1'
  run: gh pr merge --auto --squash
  env:
    GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### Manual Merge Required When

- Claude requests changes
- CI fails
- PR has `do-not-merge` label

---

## Release & Distribution

SortAI is distributed as a **direct `.app` bundle** (not via App Store).

### Building a Release

```bash
# Build release app bundle
./build.sh --app -c release

# Output at .build/release/SortAI.app
```

### Version Bumping

Version is defined in `build.sh`:
- `VERSION="1.1.0"` - Marketing version
- Build number increments automatically

Update before release:
```bash
# Edit build.sh
VERSION="1.2.0"
```

### Release Workflow

1. Update version in `build.sh`
2. Update CHANGELOG.md (or let it auto-generate)
3. Create release commit:
   ```bash
   git commit -am "chore(release): v1.2.0"
   git tag v1.2.0
   git push origin main --tags
   ```
4. Build release:
   ```bash
   ./build.sh --app -c release
   ```
5. Notarize if distributing publicly (optional)
6. Create GitHub release with .app bundle

---

## Changelog Management

CHANGELOG.md is auto-generated from conventional commits.

### Setup (One-time)

Install git-cliff:
```bash
brew install git-cliff
```

### Generate Changelog

```bash
# Generate/update CHANGELOG.md
git-cliff -o CHANGELOG.md

# Preview without writing
git-cliff --dry-run
```

### Configuration

Create `cliff.toml` in project root:

```toml
[changelog]
header = """
# Changelog

All notable changes to SortAI will be documented in this file.
"""
body = """
{% for group, commits in commits | group_by(attribute="group") %}
### {{ group | upper_first }}
{% for commit in commits %}
- {{ commit.message | upper_first }} ({{ commit.id | truncate(length=7, end="") }})\
{% endfor %}
{% endfor %}
"""
footer = ""

[git]
conventional_commits = true
filter_unconventional = true
commit_parsers = [
    { message = "^feat", group = "Features" },
    { message = "^fix", group = "Bug Fixes" },
    { message = "^refactor", group = "Refactoring" },
    { message = "^doc", group = "Documentation" },
    { message = "^test", group = "Testing" },
    { message = "^perf", group = "Performance" },
    { message = "^chore\\(release\\)", skip = true },
    { message = "^chore", group = "Miscellaneous" },
]
```

### Pre-release Workflow

```bash
# Generate changelog for upcoming release
git-cliff --unreleased -o CHANGELOG.md

# Commit changelog
git add CHANGELOG.md
git commit -m "docs: update changelog for v1.2.0"
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
| **browsermcp** | Browser testing | UI testing, screenshots |

### Verifying MCP Server Status

```bash
# Check configured servers (in ~/.cursor/mcp.json)
cat ~/.cursor/mcp.json | jq '.mcpServers | keys'
```

### Using TaskMaster for Complex Features

```bash
# Parse a feature into tasks
# mcp_taskmaster-ai_parse_prd for feature planning
# mcp_taskmaster-ai_expand_task for detailed subtasks
# mcp_taskmaster-ai_set_task_status as you complete work
```

### Memory-Based Development

```bash
# Store important decisions
# mcp_openmemory_add-memory "SortAI uses custom SQLite with SQLITE_ENABLE_SNAPSHOT=1"

# Search past decisions
# mcp_openmemory_search-memories "SQLite configuration"
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
4. Log Ralph loop sessions to `ralph-loop-log.md`

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
# mcp_openmemory_search-memories "[error message or symptom]"
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

## Rollback Procedures

When a bad commit reaches main:

### Quick Revert (Preferred)

```bash
# Revert the most recent merge commit
git revert -m 1 HEAD
git push origin main

# Or revert a specific commit
git revert <commit-sha>
git push origin main
```

### Full Reset (Emergency Only)

Use only when revert isn't possible (e.g., data corruption):

```bash
# Find the last known good commit
git log --oneline -20

# Reset main to that commit
git reset --hard <good-commit-sha>

# Force push (DANGEROUS - use only in emergencies)
git push --force-with-lease origin main
```

### After Rollback

1. Create a bugfix branch to properly fix the issue
2. Document what went wrong in Claude.md
3. Add tests to prevent recurrence

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

# Create PR (will auto-merge after CI)
gh pr create

# After auto-merge, cleanup local
git checkout main && git pull && git branch -d feature/xyz
```

### Hotfix (Direct to Main)

```bash
git checkout main
git pull
# ... fix ...
git commit -m "fix(critical): description"
git push origin main
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

# Build release
./build.sh --app -c release

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

# Force push after rebase (allowed on feature branches)
git push --force-with-lease

# View PR status
gh pr status

# Generate changelog
git-cliff -o CHANGELOG.md
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

- [x] Create `.github/workflows/ci.yml`
- [x] Create `.github/workflows/claude-review.yml`
- [ ] Add `ANTHROPIC_API_KEY` to repository secrets
- [x] Create `.claude/commands/` directory
- [x] Add custom slash commands
- [x] Verify ralph-wiggum plugin is enabled
- [ ] Configure branch protection on `main`
- [ ] Install git-cliff for changelog
- [ ] Create cliff.toml configuration

### Branch Protection Settings

In GitHub → Settings → Branches → Add rule for `main`:

- [x] Require a pull request before merging (except for hotfixes)
- [x] Require status checks to pass (CI workflow)
- [ ] Require branches to be up to date (disabled for solo)
- [x] Include administrators
- [x] Allow force pushes (for feature branches only)

---

*Last updated: 2026-01-12*
*Maintained via Claude.md continuous improvement process*
