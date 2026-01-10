---
description: "Start a bugfix branch"
argument-hint: "<issue-number-or-description>"
allowed-tools: ["Bash"]
---

# Bugfix Branch Setup

1. Check for uncommitted changes:
   ```bash
   git status --porcelain
   ```

2. Update main and create bugfix branch:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b bugfix/$ARGUMENTS
   ```

3. Confirm:
   ```bash
   git branch --show-current
   ```

Report: "🐛 Created bugfix branch: bugfix/$ARGUMENTS. Describe the bug for analysis."

