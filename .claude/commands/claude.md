---
description: Delegate a task to an autonomous Claude CLI in an isolated worktree
argument-hint: <task description>
allowed-tools: Bash(claude:*), Bash(git:*)
---
Delegated autonomously on: "$ARGUMENTS"

!`set -e
BRANCH="auto/$(date +%s)"
git stash -u 2>/dev/null || true
git worktree add -b "$BRANCH" "../wt-$BRANCH" HEAD
cd "../wt-$BRANCH"
claude -p "Complete this task: $ARGUMENTS. When done, run the project's tests and linter, and fix anything that fails before finishing. Make atomic commits as you go." \
  --dangerously-skip-permissions 2>&1 | tee "../wt-$BRANCH-log.txt"
echo "---"
echo "Branch: $BRANCH"
git log --oneline HEAD..$BRANCH 2>/dev/null || git -C "../wt-$BRANCH" log --oneline -10`

Summarize what was done, which files changed, whether tests passed, and flag anything that needs my attention. The work is on branch $BRANCH in its own worktree — review and merge when ready.
