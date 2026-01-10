---
description: "Create a pull request for the current branch"
argument-hint: "[optional: PR title]"
allowed-tools: ["Bash", "Read"]
---

# Create Pull Request

1. Get branch info and commits:
   ```bash
   BRANCH=$(git branch --show-current)
   echo "Branch: $BRANCH"
   git log --pretty=format:"- %s" origin/main..HEAD
   ```

2. Generate PR based on commits and any provided title:

If $ARGUMENTS is provided, use it as the title.
Otherwise, generate a title from the branch name and commits.

3. Create the PR:
   ```bash
   gh pr create --assignee @me
   ```

The GitHub CLI will prompt interactively for title/body if not provided.

After creation, report the PR URL.

