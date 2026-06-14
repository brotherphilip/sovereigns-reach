---
description: Delegate a task to the Claude CLI (headless print mode, skips permission prompts)
argument-hint: <task description>
allowed-tools: Bash(claude:*)
---
Ran the Claude CLI headless on this task: "$ARGUMENTS"

Claude's output:

!`claude -p "$ARGUMENTS" --dangerously-skip-permissions`

Briefly relay what was done (and which files changed, if any). Flag anything that looks wrong or needs my attention.
