SOVEREIGN'S REACH — AUTONOMOUS IMPROVEMENT LOOP (OMNISCIENCE-DELEGATED)

You (Claude) run one iteration of an indefinite improvement loop for the Godot 4 game
"Sovereign's Reach". You act as SUPERVISOR. Omniscience (qwen3-coder:30b via Ollama) does
the heavy lifting — reads files, writes code, runs checks — at zero Anthropic token cost.

Project root: /home/philip/Documents/Projects/Sovereign's Reach/
CLI tool:     python3 omniscience-cli.py --no-confirm "task"
Orientation:  You read state files yourself (small, targeted reads). Omniscience reads code.

Do NOT stop. Do NOT ask for permission. Do NOT skip steps. Follow this script exactly.
After completing your work, run /compact, schedule the next wakeup, and end your turn.

════════════════════════════════════════════
STEP 1 — ORIENT (you do this, minimal reads)
════════════════════════════════════════════

Read ONLY these three files — nothing else at this stage:
  1. loop state.md   (create with defaults if missing — see below)
  2. issue log.md    (create empty if missing — see below)
  3. phase plan.md   (note only: exists or absent, and active_phase number)

DEFAULT loop state.md (if creating for first time):
  mode: issue-fix
  active_issue: none
  active_phase: 0
  phase_plan_exists: false
  last_iteration: (today's date)
  iteration_count: 0

DEFAULT issue log.md (if creating for first time):
  # Issue Log — Sovereign's Reach
  <!-- Format: ## [ID] Title | Severity: Blocker/High/Medium/Low | Status: Open/In Progress/Resolved/Byproduct -->
  <!-- Severities: Blocker=crashes/data loss, High=broken feature, Medium=wrong behavior, Low=polish/text -->

After reading, decide which STEP to go to:

  → Open issues with Status: Open exist  →  STEP 3A (Issue Fix)
  → No issues, phase_plan_exists = false →  STEP 3C (Create Phase Plan)
  → No issues, plan exists, phases left  →  STEP 3B (Phase Step)
  → No issues, all phases complete       →  STEP 3D (Audit)

════════════════════════════════════════════
STEP 2 — PRE-DELEGATION PREP (you do this before any Omniscience call)
════════════════════════════════════════════

Before writing ANY Omniscience task prompt, read the target file yourself (the .gd file
named in the sub-task or issue). Quick scan — 2 minutes max.

Then build the task prompt to include ALL of these:
  - Exact file path: res://path/to/File.gd
  - Exact function name to add or modify
  - 4–8 lines of the CURRENT code at that location (copied verbatim)
  - Concrete description of the NEW code (pseudocode or example is fine)

WHY: Omniscience tends to explore broadly when given vague descriptions. Giving it the
current code snippet removes the need to explore and forces a "read → act" path.

OMNISCIENCE PERFORMANCE LOG (update loop state.md after each call):
  Track `omni_fail_streak: N` in loop state.md. Increment on every failure; reset to 0 on success.

  Classify each failure and patch omniscience-cli.py immediately (every fail, not just 2+):
    no_write  : write_used=false — explored but wrote nothing.
                → Patch build_system_prompt(): tighten 3-TURN WRITE RULE language.
                → Strengthen the STOP EXPLORING nudge (longer / more forceful).
    incomplete: write_used=true but < 5 lines for a feature-sized task.
                → Patch nudge to demand larger write scope explicitly.
    wrong_file: wrote to wrong file.
                → You gave a vague task — add an explicit file path to your next task prompt.
    truncated : output cut off mid-line or mid-block.
                → Split the task into a smaller subtask next iteration.
    wrong_logic: wrote but the logic is incorrect.
                → Add pseudocode or a concrete example to your next task prompt.

  After classifying, commit the omniscience-cli.py patch, note the streak in loop state.md.
  Do NOT fix the code yourself — leave the task open so the next iteration retries.

  HARD-CUT rule: only after omni_fail_streak reaches 10 on the SAME task:
    Write the code yourself with Edit/Write tools.
    Then reset omni_fail_streak: 0 in loop state.md.
    Omniscience is automatically restored for the next task — no other action needed.

════════════════════════════════════════════
STEP 3A — ISSUE FIX (delegate to Omniscience)
════════════════════════════════════════════

  a) Select the highest-priority OPEN issue (Blocker > High > Medium > Low; oldest ID wins tie).
     Update issue log.md: mark it Status: In Progress.
     Update loop state.md: active_issue=[ID].

  b) Run Omniscience with a precise task. Replace [ISSUE TITLE] and [DETAILS] with the actual
     issue content from issue log.md:

       python3 omniscience-cli.py --no-confirm \
         "Fix issue #[ID]: [ISSUE TITLE]. [DETAILS FROM ISSUE LOG]. \
         Steps: (1) search_codebase to locate relevant code, (2) read the exact files, \
         (3) implement the smallest correct fix, (4) run check_script to verify, \
         (5) report what changed and which line(s)."

     Run this via Bash. Capture the full output.

  c) REVIEW — do all of these:
     - Read the [OMNISCIENCE_RESULT] JSON at the bottom of the output.
     - Run: git -C "/home/philip/Documents/Projects/Sovereign's Reach" diff HEAD
     - Check that the diff is plausible: right file, right kind of change, not a massive rewrite.
     - If Omniscience ran tests, check they passed (look for pass counts in output).

  d) HANDLE FAILURES:
     - If write_used=true AND diff is correct: success. Reset omni_fail_streak: 0. Proceed.
     - If write_used=false OR diff is wrong/over-broad/introduces an error:
       Classify failure type (see STEP 2 PERFORMANCE LOG).
       Increment omni_fail_streak in loop state.md.
       Patch omniscience-cli.py accordingly, commit the patch.
       Leave the issue Status: In Progress — do NOT fix it yourself.
       The next loop iteration will re-enter STEP 3A and retry Omniscience on the same issue.
     - HARD-CUT exception: if omni_fail_streak has now reached 10 on this exact issue:
       Fix the code yourself with Edit/Write tools. Mark issue Resolved.
       Reset omni_fail_streak: 0 in loop state.md.

  e) Update issue log.md: Status: Resolved + one-line resolution note.
     Byproduct check: if another open issue is clearly fixed by this change, mark it
     Status: Byproduct of #[ID]. If Omniscience noted any new bugs, add them as new entries.
     Update loop state.md: active_issue=none, increment iteration_count, last_iteration=today.

  → STEP 4 (Wrap Up).

════════════════════════════════════════════
STEP 3B — PHASE STEP (delegate to Omniscience)
════════════════════════════════════════════

  a) Read phase plan.md. Find active_phase from loop state.md.
     If that phase is marked Complete, increment active_phase and use the next one.
     If all phases are Complete, go to STEP 3D.
     Identify the next pending sub-task within the active phase.

  b) Run Omniscience with a precise task. Replace [PHASE GOAL] and [SUBTASK] with real content:

       python3 omniscience-cli.py --no-confirm \
         "Phase [N] — [PHASE GOAL]. Implement this sub-task: [SUBTASK]. \
         This is a POLISH task on an existing system — do not add new systems. \
         Steps: (1) search_codebase or read_file to understand the current code, \
         (2) implement the minimal change, (3) check_script to verify, \
         (4) report exactly what changed."

     Run this via Bash. Capture the full output.

  c) REVIEW — do all of these:
     - Read the [OMNISCIENCE_RESULT] JSON.
     - Run: git -C "/home/philip/Documents/Projects/Sovereign's Reach" diff HEAD
     - Verify the diff is scoped to the sub-task only — no unrelated changes.
     - Check compile errors are absent (look for "compiles cleanly" in output).

  d) HANDLE FAILURES: same protocol as STEP 3A(d).
     If Omniscience failed: classify, increment omni_fail_streak, patch omniscience-cli.py,
     leave the sub-task undone. Hard-cut only at streak = 10, then reset streak to 0.

  e) Mark the sub-task as done in phase plan.md (append "✓" or strike through it).
     If ALL sub-tasks for this phase are now done, mark the phase Status: Complete
     and increment active_phase in loop state.md.
     Update loop state.md: last_iteration=today, increment iteration_count.

  → STEP 4 (Wrap Up).

════════════════════════════════════════════
STEP 3C — CREATE PHASE PLAN (delegate to Omniscience)
════════════════════════════════════════════

Run once. Issue queue is empty. No phase plan exists yet.

  a) Run Omniscience to do the full audit and write the plan:

       python3 omniscience-cli.py --no-confirm \
         "Read GAME DESIGN DOC.md, ROADMAP.md, CHANGELOG.md fully. Then skim all .gd files \
         (use list_files + read_file or search_codebase) looking for thin implementations, \
         incomplete systems, and missing polish. Based on this, write phase plan.md with \
         5-10 phases. Each phase: focused goal, 3-8 concrete sub-tasks with file targets, \
         Status: Pending. Focus 100% on polishing EXISTING systems — no new features. \
         Format per the loop protocol in your system prompt."

     Run via Bash. Capture the full output.

  b) REVIEW the generated phase plan.md:
     - Read phase plan.md yourself.
     - Check each sub-task: does the file target actually exist? Is it already implemented?
       (Cross-reference what you know from OMNISCIENCE_LOG.md and ROADMAP.md.)
     - Correct any sub-tasks that target non-existent files or describe already-done work.

  c) Update loop state.md: phase_plan_exists=true, active_phase=1, mode=phase,
     last_iteration=today, increment iteration_count.

  → STEP 4 (Wrap Up). Phase work begins next iteration.

════════════════════════════════════════════
STEP 3D — AUDIT (delegate to Omniscience)
════════════════════════════════════════════

All phases complete, no open issues.

  a) Run Omniscience to audit:

       python3 omniscience-cli.py --no-confirm \
         "Audit the project for issues. (1) run_shell: grep -rn 'TODO\|FIXME\|BUG\|HACK\|XXX' \
         simulation/ view/ to find flagged code. (2) Read GAME DESIGN DOC.md and spot-check \
         3-5 described features against the actual code. (3) Read CHANGELOG.md last 10 entries \
         and verify 3 items still exist in code. (4) Report all genuine issues found with \
         file:line references. Do NOT report style preferences or cosmetic nits."

     Run via Bash.

  b) Parse the output: if Omniscience reported genuine issues, add each to issue log.md
     with a new ID, appropriate severity, Status: Open.
     Update loop state.md: mode=issue-fix if any issues added.

  c) If nothing found: write "AUDIT COMPLETE — ALL CLEAR [date]" into loop state.md notes.

  Update loop state.md: last_iteration=today, increment iteration_count.
  → STEP 4 (Wrap Up).

════════════════════════════════════════════
STEP 3E — IN-GAME SCENE TEST (you do this after every code change)
════════════════════════════════════════════

Run this AFTER every iteration that modified any .gd file — before committing.
Goal: catch parse errors and scene-load crashes before they reach the user.

  a) Write and run a headless scene-load test via Bash:

       cat > /tmp/test_scenes.gd << 'GDEOF'
       extends SceneTree
       func _init() -> void:
           await create_timer(0.2).timeout
           var scenes = [
               "res://view/cityview/CityViewScene.tscn",
               "res://view/main/Main.tscn",
           ]
           var failed := false
           for s in scenes:
               var err = change_scene_to_file(s)
               if err != OK:
                   print("FAIL: %s — err %d" % [s, err])
                   failed = true
               else:
                   await create_timer(0.5).timeout
                   print("OK: %s" % s)
           if not failed:
               print("ALL_SCENES_OK")
           quit(0 if not failed else 1)
       GDEOF
       cd "/home/philip/Documents/Projects/Sovereign's Reach" && timeout 30 godot --headless --script /tmp/test_scenes.gd 2>&1

  b) Check output:
     - ALL_SCENES_OK in output → proceed to STEP 4.
     - Any "Parse Error" / "Compile Error" / "FAIL:" line → stop and fix before committing.
       Common causes: duplicate variable names, bad preload path, missing key in a dict.
       Fix with Edit tool, then re-run the test until ALL_SCENES_OK.

════════════════════════════════════════════
STEP 4 — WRAP UP (you do this)
════════════════════════════════════════════

  a) DOC UPDATES — if Omniscience made code changes this iteration:
     Run: git -C "/home/philip/Documents/Projects/Sovereign's Reach" diff HEAD --stat
     For each changed file, update the relevant section of GAME DESIGN DOC.md if the
     feature it describes changed. Do not rewrite unrelated sections.

     Append to CHANGELOG.md:
       ## [Iteration N] YYYY-MM-DD — [one-line summary of what changed]
       - Delegated to: Omniscience (qwen3-coder:30b)
       - What changed and why
       - Issues resolved: #ID (if any)
       - Issues discovered: #ID (if any)
       - Supervisor correction: [describe any fix you made, or "none"]

     Mark any now-complete ROADMAP.md items (do not add new ones).

     If no code changes this iteration: still append a CHANGELOG entry.

  b) Confirm loop state.md is fully up to date.

  c) SELF-IMPROVEMENT CHECK — every iteration that involved Omniscience:
     - SUCCESS: write_used=true AND diff is correct and complete.
       Reset omni_fail_streak: 0 in loop state.md. No other action needed.
     - ANY FAIL (write_used=false OR diff is wrong/incomplete/over-broad):
       Classify failure type per STEP 2 PERFORMANCE LOG.
       Increment omni_fail_streak in loop state.md.
       Patch omniscience-cli.py (build_system_prompt() or nudge block) to address root cause.
       Commit: git add omniscience-cli.py && git commit -m "omniscience: <type> — [reason]"
       Do NOT write the code yourself — leave the task open for retry next iteration.
     - HARD-CUT (only when omni_fail_streak = 10 on the same task):
       Write the code yourself with Edit/Write. Complete the task fully.
       Note in CHANGELOG: "Supervisor hard-cut after 10 Omniscience failures — [reason]"
       Reset omni_fail_streak: 0. Omniscience is restored for the next task automatically.

  d) Run /compact to compress conversation context.

  d) SELF-PACE — schedule next wakeup:
     - After a code fix or phase step: 60–120 seconds
     - After phase plan creation or audit-all-clear: 270 seconds
     - Never more than 270 seconds.

Do NOT summarise. Do NOT ask the user anything. Schedule the wakeup and stop.
