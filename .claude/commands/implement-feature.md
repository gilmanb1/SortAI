---
description: "Use Ralph loop to implement a well-defined feature"
argument-hint: "<feature-requirements>"
allowed-tools: ["Bash"]
---

# Feature Implementation with Ralph Loop

This command sets up a Ralph loop for implementing a feature with clear requirements.

IMPORTANT: Before using this, ensure:
1. You have clear, testable requirements
2. You know the success criteria
3. You've set a reasonable iteration limit

The user provided: $ARGUMENTS

Now start the Ralph loop by running:

```
/ralph-loop "$ARGUMENTS

Implementation approach:
1. Write failing tests for the requirements
2. Implement the minimum code to pass
3. Run tests: swift test --filter [TestName] -Xcc -I\$(pwd)/.local/sqlite/install -Xlinker -L\$(pwd)/.local/sqlite/install
4. If tests fail, analyze output and fix
5. Refactor if needed
6. Repeat until all requirements met

Output <promise>FEATURE COMPLETE</promise> when all tests pass and requirements are met." --completion-promise "FEATURE COMPLETE" --max-iterations 20
```

Guide the user through setting appropriate iteration limits and completion criteria.

