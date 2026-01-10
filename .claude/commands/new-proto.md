---
description: "Start a prototype/exploration branch"
argument-hint: "<experiment-name>"
allowed-tools: ["Bash"]
---

# Prototype Branch Setup

Create a branch for experimental work that may or may not be merged.

1. Check current state:
   ```bash
   git status --porcelain
   ```

2. Create prototype branch from current main:
   ```bash
   git checkout main
   git pull origin main
   git checkout -b proto/$ARGUMENTS
   ```

3. Confirm:
   ```bash
   git branch --show-current
   ```

Report: "🧪 Created prototype branch: proto/$ARGUMENTS. This is for experimentation - feel free to try things that might not work!"

