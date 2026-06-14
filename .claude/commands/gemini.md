---
description: Delegate a task to the Gemini CLI (your subscription, headless, auto-approves edits)
argument-hint: <task description>
allowed-tools: Bash(gemini:*)
---
Ran the Gemini CLI headless on this task: "$ARGUMENTS"

Gemini's output:

!`gemini -p "$ARGUMENTS" --skip-trust --approval-mode yolo`

Briefly relay what Gemini did (and which files it changed, if any). Flag anything that looks wrong or needs my attention.
