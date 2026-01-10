---
description: "Merge approved PR and cleanup branch"
allowed-tools: ["Bash"]
---

# Ship It! 🚀

Merge the current PR and cleanup.

1. Check current branch and PR status:
   ```bash
   git branch --show-current
   gh pr status
   ```

2. Merge with squash:
   ```bash
   gh pr merge --squash --delete-branch
   ```

3. Return to main and update:
   ```bash
   git checkout main
   git pull origin main
   ```

4. Confirm:
   ```bash
   git log --oneline -3
   ```

Report: "🚀 Shipped! PR merged to main and branch cleaned up."

