---
description: "Start a new feature branch with proper setup"
argument-hint: "<feature-name>"
allowed-tools: ["Bash"]
---

# New Feature Setup

Execute these steps in order:

1. Check for uncommitted changes:
   ```bash
   git status --porcelain
   ```
   If there are changes, warn the user and ask if they want to stash.

2. Update main and create the feature branch:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feature/$ARGUMENTS
   ```

3. Confirm the branch was created:
   ```bash
   git branch --show-current
   ```

Report: "✅ Created feature branch: feature/$ARGUMENTS from latest main. Ready for development."

