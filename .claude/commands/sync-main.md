---
description: "Sync current branch with latest main (rebase)"
allowed-tools: ["Bash"]
---

# Sync with Main Branch

1. Get current branch name:
   ```bash
   git branch --show-current
   ```

2. Fetch and rebase:
   ```bash
   git fetch origin
   git rebase origin/main
   ```

If there are conflicts:
- List the conflicted files
- Help resolve each conflict
- Continue the rebase with `git rebase --continue`

If rebase succeeds, report the number of commits replayed.

