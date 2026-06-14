#!/usr/bin/env python3
"""
Omniscience CLI — standalone Ollama tool-calling agent for Sovereign's Reach.
Mirrors the agent.gd loop so Omniscience can read and edit files without the
Godot editor being open. Claude supervises: write operations require Y/n confirmation.

Usage:
    python3 omniscience-cli.py "your task"
    python3 omniscience-cli.py --model qwen3-coder:30b "task"
    python3 omniscience-cli.py --no-confirm "task"   # skip write confirmations
    python3 omniscience-cli.py --dry-run "task"      # read-only, no writes at all
"""

import argparse, json, os, re, shutil, subprocess, sys, urllib.request, urllib.error
from pathlib import Path

# ── Config ─────────────────────────────────────────────────────────────────────
PROJECT_ROOT   = Path(__file__).parent.resolve()
OLLAMA_URL     = "http://127.0.0.1:11434/v1/chat/completions"
DEFAULT_MODEL  = "qwen3-coder:30b"
TEMPERATURE    = 0.2
MAX_ITERS      = 10
MAX_NUDGES     = 3
RAG_INDEX      = PROJECT_ROOT / "addons/omniscience/rag/index.json"
EMBED_URL      = "http://127.0.0.1:11434/api/embed"
EMBED_MODEL    = "nomic-embed-text"

WRITE_TOOLS = {"write_file", "replace_in_file", "replace_lines", "run_shell"}

# ── Tool schemas (CLI-compatible subset of editor_tools.gd SCHEMAS) ────────────
SCHEMAS = [
    {"type": "function", "function": {
        "name": "search_codebase",
        "description": "Semantically search the codebase for relevant code or docs. Returns the top matching file chunks. Use this FIRST to locate relevant code before calling read_file on large files.",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string", "description": "Natural-language description of what you are looking for."},
            "top_k": {"type": "integer", "description": "Number of results (default 5)."},
        }, "required": ["query"]},
    }},
    {"type": "function", "function": {
        "name": "list_files",
        "description": "List files in the project. Use to discover where things are before reading or editing.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "Directory, e.g. res:// (default) or res://simulation/combat."},
            "pattern": {"type": "string", "description": "Optional glob filter, e.g. *.gd."},
            "recursive": {"type": "boolean", "description": "Recurse into subfolders (default true)."},
        }},
    }},
    {"type": "function", "function": {
        "name": "read_file",
        "description": "Read any project file. Each line is prefixed 'N| ' for targeting edits — do NOT include that prefix in old_string or new_text.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "res:// path, e.g. res://view/micro/BuildingLayer.gd"},
        }, "required": ["path"]},
    }},
    {"type": "function", "function": {
        "name": "check_script",
        "description": "Compile-check a GDScript file with Godot's parser. Returns exact errors with line numbers, or OK. Use after every edit to verify the fix.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "res:// path to the .gd file."},
        }, "required": ["path"]},
    }},
    {"type": "function", "function": {
        "name": "read_console",
        "description": "Read recent Godot game console output (runtime errors, print output). Call when asked to fix a runtime error.",
        "parameters": {"type": "object", "properties": {
            "lines": {"type": "integer", "description": "How many trailing lines to return (default 200)."},
        }},
    }},
    {"type": "function", "function": {
        "name": "write_file",
        "description": "Create or overwrite a file. For .gd files the result is automatically compile-checked. Prefer replace_lines or replace_in_file for small edits — only use this to create new files or fully rewrite one.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "res:// path to write."},
            "content": {"type": "string", "description": "Complete new file content."},
        }, "required": ["path", "content"]},
    }},
    {"type": "function", "function": {
        "name": "replace_in_file",
        "description": "Make a surgical edit: replace an exact snippet with new text. PREFER THIS for small changes. old_string must be copied verbatim from a read_file result you actually saw — never reconstruct from memory.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "old_string": {"type": "string", "description": "Exact text to replace (copy verbatim, including indentation)."},
            "new_string": {"type": "string", "description": "Replacement text."},
            "replace_all": {"type": "boolean", "description": "Replace every occurrence (default false)."},
        }, "required": ["path", "old_string", "new_string"]},
    }},
    {"type": "function", "function": {
        "name": "replace_lines",
        "description": "Replace a range of lines (1-based, inclusive). THE MOST RELIABLE way to fix a specific line — use line numbers from check_script errors or grep -n. No text matching needed.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "start_line": {"type": "integer", "description": "First line to replace (1-based, inclusive)."},
            "end_line": {"type": "integer", "description": "Last line to replace (same as start_line for one line)."},
            "new_text": {"type": "string", "description": "Replacement text (correct indentation; no trailing newline)."},
        }, "required": ["path", "start_line", "end_line", "new_text"]},
    }},
    {"type": "function", "function": {
        "name": "run_shell",
        "description": "Run a shell command in the project directory. Universal escape hatch: git, grep, file ops, godot --headless for tests. Use real paths relative to project root, NOT res://.",
        "parameters": {"type": "object", "properties": {
            "command": {"type": "string", "description": "Full command, e.g. grep -rn 'func tick' simulation/"},
        }, "required": ["command"]},
    }},
]

# ── Path helpers ───────────────────────────────────────────────────────────────
def res_to_fs(path: str) -> Path:
    p = path.strip()
    if p.startswith("res://"):
        p = p[6:]
    elif p.startswith("user://"):
        raise ValueError(f"user:// paths are not accessible from the CLI: {path}")
    return PROJECT_ROOT / p

def fs_to_res(path: Path) -> str:
    return "res://" + str(path.relative_to(PROJECT_ROOT)).replace("\\", "/")

def find_godot() -> str | None:
    env = os.environ.get("GODOT_BIN")
    if env and Path(env).exists():
        return env
    for name in ("godot4", "godot", "godot.x86_64", "Godot_v4"):
        found = shutil.which(name)
        if found:
            return found
    return None

# ── Result helpers ─────────────────────────────────────────────────────────────
def _ok(result) -> dict:
    return {"ok": True, "result": result}

def _err(msg: str) -> dict:
    return {"ok": False, "error": msg}

def _with_line_numbers(text: str) -> str:
    lines = text.split("\n")
    w = len(str(len(lines)))
    return "\n".join(f"{i+1:{w}}| {line}" for i, line in enumerate(lines))

def _decode_escaped_whitespace(text: str) -> str:
    # Always decode escape sequences — the early-return on "\n" was wrong:
    # it prevented \t from being converted when new_text had both \n and \t.
    if "\\t" in text or "\\n" in text or "\\r" in text:
        return (text.replace("\\r\\n", "\n").replace("\\n", "\n")
                    .replace("\\t", "\t").replace("\\r", "\n"))
    return text

# ── Tool implementations ───────────────────────────────────────────────────────
def tool_search_codebase(args: dict) -> dict:
    query = args.get("query", "")
    top_k = int(args.get("top_k", 5))
    if not query:
        return _err("No query given.")
    if RAG_INDEX.exists():
        return _rag_search(query, top_k)
    result = subprocess.run(
        ["grep", "-rn", "--include=*.gd", "--include=*.md", "-i",
         query, "."],
        capture_output=True, text=True, cwd=str(PROJECT_ROOT), timeout=15
    )
    out = result.stdout.strip()
    if len(out) > 4000:
        out = out[:4000] + "\n…(truncated — run build_index.py for semantic search)"
    return _ok(f"(grep fallback — no RAG index found)\n{out}" if out else "(no matches)")

def _cosine_sim(a: list, b: list) -> float:
    dot = sum(x * y for x, y in zip(a, b))
    mag_a = sum(x * x for x in a) ** 0.5
    mag_b = sum(x * x for x in b) ** 0.5
    return dot / (mag_a * mag_b) if mag_a and mag_b else 0.0

def _embed(text: str) -> list:
    payload = json.dumps({"model": EMBED_MODEL, "input": text}).encode()
    req = urllib.request.Request(EMBED_URL, data=payload,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())["embeddings"][0]

def _rag_search(query: str, top_k: int) -> dict:
    index = json.loads(RAG_INDEX.read_text())
    chunks = index["chunks"]
    try:
        q_emb = _embed(query)
    except Exception as e:
        return _err(f"Embedding failed: {e}")
    scored = sorted(
        ((c, _cosine_sim(q_emb, c["embedding"])) for c in chunks),
        key=lambda x: x[1], reverse=True
    )
    parts = [
        f"=== {c['path']} | {c['heading']} (score {s:.3f}) ===\n{c['text']}"
        for c, s in scored[:top_k]
    ]
    return _ok("\n\n".join(parts))

def tool_list_files(args: dict) -> dict:
    dir_path = args.get("path", "res://")
    pattern = args.get("pattern", "*")
    recursive = args.get("recursive", True)
    try:
        fs_dir = res_to_fs(dir_path)
    except ValueError as e:
        return _err(str(e))
    if not fs_dir.is_dir():
        return _err(f"Directory not found: {dir_path}")
    glob_fn = fs_dir.rglob if recursive else fs_dir.glob
    results = sorted(
        fs_to_res(p) for p in glob_fn(pattern)
        if p.is_file() and ".godot" not in p.parts
    )
    return _ok("\n".join(results) if results else f"(no matching files in {dir_path})")

def tool_read_file(args: dict) -> dict:
    path = args.get("path", "")
    if not path:
        return _err("No path given.")
    try:
        fs = res_to_fs(path)
    except ValueError as e:
        return _err(str(e))
    if not fs.exists():
        return _err(f"File not found: {path}")
    try:
        text = fs.read_text(encoding="utf-8")
    except Exception as e:
        return _err(f"Could not read {path}: {e}")
    return _ok({"path": path, "content": _with_line_numbers(text)})

def _write_file_raw(path: str, content: str) -> dict:
    try:
        fs = res_to_fs(path)
    except ValueError as e:
        return _err(str(e))
    fs.parent.mkdir(parents=True, exist_ok=True)
    if path.endswith(".gd") and not content.endswith("\n"):
        content += "\n"
    try:
        fs.write_text(content, encoding="utf-8")
    except Exception as e:
        return _err(f"Could not write {path}: {e}")
    msg = f"Wrote {len(content)} chars to {path}."
    if path.endswith(".gd"):
        check = tool_check_script({"path": path})
        msg += f"\nCompile check: {check.get('result', check.get('error', '?'))}"
    return _ok(msg)

def tool_write_file(args: dict) -> dict:
    path = args.get("path", "")
    content = _decode_escaped_whitespace(args.get("content", ""))
    if not path:
        return _err("No path given.")
    return _write_file_raw(path, content)

def _find_flexible_block(original: str, needle: str) -> str:
    orig_lines = original.split("\n")
    ndl_lines = needle.split("\n")
    while ndl_lines and not ndl_lines[-1].strip():
        ndl_lines.pop()
    while ndl_lines and not ndl_lines[0].strip():
        ndl_lines.pop(0)
    if not ndl_lines:
        return ""
    n = len(ndl_lines)
    matches = [
        "\n".join(orig_lines[i:i+n])
        for i in range(len(orig_lines) - n + 1)
        if all(orig_lines[i+j].strip() == ndl_lines[j].strip() for j in range(n))
    ]
    return matches[0] if len(matches) == 1 else ""

def tool_replace_in_file(args: dict) -> dict:
    path = args.get("path", "")
    old_str = _decode_escaped_whitespace(args.get("old_string", ""))
    new_str = _decode_escaped_whitespace(args.get("new_string", ""))
    replace_all = args.get("replace_all", False)
    if not path:
        return _err("No path given.")
    if not old_str:
        return _err("old_string is empty.")
    if old_str == new_str:
        return _err("old_string and new_string are identical — no-op.")
    try:
        fs = res_to_fs(path)
    except ValueError as e:
        return _err(str(e))
    if not fs.exists():
        return _err(f"File not found: {path}")
    original = fs.read_text(encoding="utf-8")
    count = original.count(old_str)
    if count >= 1:
        if count > 1 and not replace_all:
            return _err(f"old_string appears {count}× in {path}. Add more context or set replace_all=true.")
        updated = original.replace(old_str, new_str) if replace_all else original.replace(old_str, new_str, 1)
        return _write_file_raw(path, updated)
    block = _find_flexible_block(original, old_str)
    if not block:
        return _err(f"old_string not found in {path}. Copy exact lines from a read_file result.")
    if original.count(block) != 1:
        return _err(f"Matched text is ambiguous in {path}. Include more surrounding lines.")
    return _write_file_raw(path, original.replace(block, new_str, 1))

def tool_replace_lines(args: dict) -> dict:
    path = args.get("path", "")
    start = int(args.get("start_line", 0))
    end = int(args.get("end_line", 0))
    new_text = _decode_escaped_whitespace(args.get("new_text", ""))
    if not path:
        return _err("No path given.")
    try:
        fs = res_to_fs(path)
    except ValueError as e:
        return _err(str(e))
    if not fs.exists():
        return _err(f"File not found: {path}")
    original = fs.read_text(encoding="utf-8")
    had_trailing = original.endswith("\n")
    if had_trailing:
        original = original[:-1]
    lines = original.split("\n")
    if start < 1 or end < start or end > len(lines):
        return _err(f"Invalid range {start}-{end}; file has {len(lines)} lines.")
    replacement = new_text.split("\n") if new_text else []
    combined = lines[:start-1] + replacement + lines[end:]
    updated = "\n".join(combined) + ("\n" if had_trailing else "")
    return _write_file_raw(path, updated)

def tool_run_shell(args: dict) -> dict:
    command = args.get("command", "").strip()
    if not command:
        return _err("Empty command.")
    result = subprocess.run(
        command, shell=True, capture_output=True, text=True,
        cwd=str(PROJECT_ROOT), timeout=120
    )
    out = (result.stdout + result.stderr).strip()
    if len(out) > 8000:
        out = out[:8000] + "\n…(truncated)"
    return _ok(f"exit {result.returncode}\n{out}")

def tool_check_script(args: dict) -> dict:
    path = args.get("path", "")
    if not path:
        return _err("No path given.")
    try:
        fs = res_to_fs(path)
    except ValueError as e:
        return _err(str(e))
    if not fs.exists():
        return _err(f"File not found: {path}")
    godot = find_godot()
    if not godot:
        return _err("Godot not found. Set GODOT_BIN env var or add godot4 to PATH.")
    result = subprocess.run(
        [godot, "--headless", "--check-only", "--script", str(fs),
         "--path", str(PROJECT_ROOT), "--quit"],
        capture_output=True, text=True, timeout=30
    )
    all_out = (result.stdout + result.stderr).strip()
    error_lines = [l for l in all_out.split("\n") if "Error" in l or "ERROR" in l]
    if not error_lines:
        return _ok(f"OK — {path} compiles cleanly.")
    return _ok(f"{path} has errors:\n" + "\n".join(error_lines))

def tool_read_console(args: dict) -> dict:
    n = int(args.get("lines", 200))
    candidates = [
        Path.home() / ".local/share/godot/app_userdata/Sovereign's Reach/logs/godot.log",
        Path("/tmp/godot.log"),
    ]
    log_path = None
    for c in candidates:
        if c.exists():
            log_path = c
            break
    if not log_path:
        for p in Path.home().rglob("godot.log"):
            log_path = p
            break
    if not log_path:
        return _err("No Godot log file found. Run the project first.")
    text = log_path.read_text(encoding="utf-8", errors="replace")
    tail = "\n".join(text.split("\n")[-n:])
    return _ok(f"Source: {log_path}\n{tail}")

# ── Tool dispatch ──────────────────────────────────────────────────────────────
_TOOL_MAP = {
    "search_codebase": tool_search_codebase,
    "list_files":      tool_list_files,
    "read_file":       tool_read_file,
    "check_script":    tool_check_script,
    "read_console":    tool_read_console,
    "write_file":      tool_write_file,
    "replace_in_file": tool_replace_in_file,
    "replace_lines":   tool_replace_lines,
    "run_shell":       tool_run_shell,
}

def execute_tool(name: str, args: dict) -> dict:
    fn = _TOOL_MAP.get(name)
    if fn is None:
        return _err(f"Unknown tool: {name}. Available: {', '.join(_TOOL_MAP)}")
    return fn(args)

# ── Confirmation & display ─────────────────────────────────────────────────────
def describe_call(name: str, args: dict) -> str:
    if name == "write_file":
        return f"Write {len(args.get('content',''))} chars to {args.get('path','?')}"
    if name == "replace_in_file":
        return (f"In {args.get('path','?')}, replace:\n"
                f"    {str(args.get('old_string',''))[:120]}\n"
                f"  with:\n"
                f"    {str(args.get('new_string',''))[:120]}")
    if name == "replace_lines":
        return (f"In {args.get('path','?')}, replace lines "
                f"{args.get('start_line','?')}–{args.get('end_line','?')} with:\n"
                f"    {str(args.get('new_text',''))[:120]}")
    if name == "run_shell":
        return f"Run shell: {args.get('command','?')}"
    return f"Run {name}({args})"

def call_summary(args: dict) -> str:
    items = [f"{k}={str(v)[:40]}" for k, v in args.items() if k != "content"]
    return ", ".join(items)

# ── Text tool call parser (port of api_client.gd _parse_text_tool_calls) ──────
def parse_text_tool_calls(content: str) -> tuple:
    calls = []
    fn_re    = re.compile(r'(?s)<function=([^>\s]+)\s*>(.*?)</function>')
    param_re = re.compile(r'(?s)<parameter=([^>\s]+)\s*>(.*?)</parameter>')
    for m in fn_re.finditer(content):
        fname = m.group(1).strip()
        args = {}
        for pm in param_re.finditer(m.group(2)):
            val = pm.group(2)
            if val.startswith("\n"):
                val = val[1:]
            if val.endswith("\n"):
                val = val[:-1]
            args[pm.group(1).strip()] = val
        calls.append({
            "id": f"call_{len(calls)}", "type": "function",
            "function": {"name": fname, "arguments": json.dumps(args)},
        })
    if not calls:
        tc_re = re.compile(r'(?s)<tool_call>\s*(\{.*?\})\s*</tool_call>')
        for m in tc_re.finditer(content):
            try:
                parsed = json.loads(m.group(1))
                calls.append({
                    "id": f"call_{len(calls)}", "type": "function",
                    "function": {
                        "name": parsed.get("name", ""),
                        "arguments": json.dumps(parsed.get("arguments", {})),
                    },
                })
            except json.JSONDecodeError:
                pass
    cleaned = content
    if calls:
        cleaned = fn_re.sub("", content)
        cleaned = re.sub(r'(?s)<tool_call>.*?</tool_call>', "", cleaned).strip()
    return calls, cleaned

# ── Streaming chat completion ──────────────────────────────────────────────────
def chat_completion(messages: list, tools: list, model: str) -> dict:
    payload = {"model": model, "messages": messages,
               "stream": True, "temperature": TEMPERATURE}
    if tools:
        payload["tools"] = tools
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        OLLAMA_URL, data=data,
        headers={"Content-Type": "application/json",
                 "Accept": "text/event-stream"}
    )
    content = ""
    tool_calls: list = []
    print("  ⏳", end="", flush=True)
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            for raw in resp:
                line = raw.decode("utf-8").strip()
                if not line.startswith("data:"):
                    continue
                payload_str = line[5:].strip()
                if payload_str == "[DONE]":
                    break
                try:
                    chunk = json.loads(payload_str)
                except json.JSONDecodeError:
                    continue
                choices = chunk.get("choices", [])
                if not choices:
                    continue
                delta = choices[0].get("delta", {})
                piece = delta.get("content") or ""
                if piece:
                    content += piece
                    print(".", end="", flush=True)
                for tc in delta.get("tool_calls", []):
                    idx = int(tc.get("index", 0))
                    while len(tool_calls) <= idx:
                        tool_calls.append({
                            "id": "", "type": "function",
                            "function": {"name": "", "arguments": ""},
                        })
                    entry = tool_calls[idx]
                    if tc.get("id"):
                        entry["id"] = tc["id"]
                    fn = tc.get("function", {})
                    if fn.get("name"):
                        entry["function"]["name"] = fn["name"]
                    entry["function"]["arguments"] += fn.get("arguments", "")
    except urllib.error.URLError as e:
        print()
        raise RuntimeError(f"Ollama API unreachable: {e}")
    print()
    message: dict = {"role": "assistant", "content": content}
    if tool_calls:
        message["tool_calls"] = tool_calls
    else:
        recovered, cleaned = parse_text_tool_calls(content)
        if recovered:
            message["content"] = cleaned
            message["tool_calls"] = recovered
    return message

# ── System prompt ──────────────────────────────────────────────────────────────
def build_system_prompt() -> str:
    return f"""You are Omniscience, an autonomous AI developer working on the Godot 4 game \
"Sovereign's Reach" (project root: {PROJECT_ROOT}). You run from the command line (not inside \
the Godot editor). You can read and edit any project file, run shell commands, and check \
GDScript for parse errors.

ALWAYS act by emitting tool calls. Never narrate — emit the tool call immediately. \
Stop only when the task is fully done and verified, or you are genuinely blocked.

MANDATORY ACTING RULES — violating these is a failure:
- ONE-READ RULE: read each file AT MOST ONCE. After you read a file, act on it immediately. \
Do not read more files "for context" — you have enough. Read → Edit → Verify. Three steps only.
- 3-TURN WRITE RULE: you MUST call a write tool (replace_lines, replace_in_file, or write_file) \
by turn 3 of any session. If you are on turn 3 and have not written, emit replace_lines NOW \
based on what you have already read.
- NO BROAD EXPLORATION: when given a target file path, read ONLY that file. Do not read \
GameState.gd, MainController.gd, or any file not named in the task. If you need a line number \
for a symbol, use run_shell(grep -n "symbol" path/to/file.gd) — one grep, then act.
- COMPLETE THE FEATURE: writing 1–3 lines when the task requires a new function or animation \
is a failure. The task is done only when check_script passes AND the full described behaviour \
is implemented.
- NO CONVERSATIONAL DRIFT: you are a developer agent, not a chat assistant. NEVER produce \
marketing summaries, "pitch decks", feature wish-lists, or trailing offers like "would you like \
me to…". Do not editorialize about the design. Emit tool calls and concrete findings only.

AUDIT / REPORT MODE — when the task says "audit", "report", "check", "verify", or "spot-check" \
(and does NOT ask you to change code), the WRITE-by-turn-3 and ONE-READ and NO-EXPLORATION rules \
above are SUSPENDED. In this mode you SHOULD read many files (read_file / search_codebase / \
run_shell grep) to gather evidence — that is the job, not a violation. Do NOT call a write tool. \
Finish by emitting a plain-text findings list: each genuine issue as `path/to/File.gd:LINE — \
one-line description of the actual bug`. If you find nothing after checking, end with exactly \
`AUDIT RESULT: no issues found`. Never substitute a document summary for the audit.

How to work:
- PREFERRED edit flow: (1) read_file on the target file ONLY. (2) Identify exact lines to change. \
(3) replace_lines(path, start, end, new_text) by line number. (4) check_script to verify.
- Use replace_in_file for short distinctive snippets; write_file only for new files or full rewrites.
- GROUNDING RULE: never hallucinate file contents. Copy old_string verbatim from a read_file \
result you actually saw in this conversation.
- INDENTATION: this project uses TABS. Match surrounding code's exact indentation.
- Paths: tools take res:// paths (e.g. res://view/micro/BuildingLayer.gd). run_shell uses \
paths relative to project root (e.g. view/micro/BuildingLayer.gd).
- Godot 4 GDScript only. clampf/clampi/lerp are global functions, NOT methods.
- If a tool errors, read the message, fix the real cause, retry at most twice, then stop.

LOOP PROTOCOL — at the start of every loop iteration, read:
  loop state.md  → mode (issue-fix / phase), active_issue, active_phase, phase_plan_exists
  issue log.md   → open issues with ## [ID] Title | Severity | Status
  phase plan.md  → 10-phase polish plan with Status: Pending / In Progress / Complete

Decision tree:
  Open issues exist?       → fix highest-priority (Blocker > High > Medium > Low; oldest wins tie)
  No issues + no plan?     → create phase plan.md (5–10 phases, polish only, no new systems)
  No issues + plan exists? → execute next incomplete phase sub-task
  All phases done?         → audit: grep TODO/FIXME/BUG/HACK, check doc consistency

One-item rule: do ONE issue fix OR ONE phase sub-task per session. No batching.
Always update loop state.md + CHANGELOG.md before finishing."""

# ── Agent loop ────────────────────────────────────────────────────────────────
def run_agent(task: str, model: str, confirm_writes: bool, dry_run: bool) -> dict:
    messages = [
        {"role": "system", "content": build_system_prompt()},
        {"role": "user", "content": task},
    ]
    iteration = 0
    nudges = 0
    tools_used = False
    write_used = False
    actions: list[str] = []

    # Audit/report tasks are read-only: reading many files then answering in plain
    # text is the correct outcome, so the write-by-turn-3 nudge must NOT fire.
    _t = task.lower()
    is_audit = (any(k in _t for k in ("audit", "spot-check", "spot check", "report all",
                "verify ", "check doc")) and "implement" not in _t and "fix issue" not in _t)

    while iteration < MAX_ITERS:
        print(f"\n[Omniscience turn {iteration + 1}/{MAX_ITERS}]")
        message = chat_completion(messages, SCHEMAS, model)
        messages.append(message)

        tool_call_list = message.get("tool_calls", [])

        if not tool_call_list:
            if not is_audit and tools_used and not write_used and nudges < MAX_NUDGES:
                nudges += 1
                print(f"  ⚡ Nudge {nudges}/{MAX_NUDGES}: model investigated but did not act.")
                messages.append({"role": "user", "content":
                    "STOP EXPLORING. You have read enough. The task is NOT done — you have "
                    "made zero code changes. Act NOW:\n"
                    "1. Look at the file you just read. Find the exact lines to add or change.\n"
                    "2. Call replace_lines(path=<res://path>, start_line=N, end_line=M, "
                    "new_text=<replacement>) using line numbers from the read_file output.\n"
                    "   OR call replace_in_file with text you literally saw in the file.\n"
                    "3. Then call check_script to verify.\n"
                    "Do NOT read more files. Do NOT run more shell commands. "
                    "Emit replace_lines or replace_in_file RIGHT NOW."
                })
                continue
            break  # Answered in plain text — done.

        tool_results = []
        for call in tool_call_list:
            fn       = call.get("function", {})
            name     = fn.get("name", "")
            try:
                args = json.loads(fn.get("arguments", "{}"))
            except json.JSONDecodeError:
                args = {}

            is_write = name in WRITE_TOOLS
            tools_used = True

            if is_write and dry_run:
                result = _err("Dry-run mode: write operations are disabled.")
                print(f"  🚫 {name}({call_summary(args)}) — blocked (dry-run)")
            elif is_write and confirm_writes:
                desc = describe_call(name, args)
                print(f"\n  ⚠️  Omniscience wants to:\n  {desc}")
                answer = input("  Allow? [Y/n]: ").strip().lower()
                if answer not in ("", "y", "yes"):
                    result = _err("User declined. Do not retry; ask what they want instead.")
                    print(f"  ✖ {name} — declined by user")
                else:
                    result = execute_tool(name, args)
                    status = "✔" if result.get("ok") else "✖"
                    print(f"  {status} {name}")
                    if result.get("ok"):
                        write_used = True
                        actions.append(f"{name}({call_summary(args)})")
            else:
                result = execute_tool(name, args)
                status = "✔" if result.get("ok") else "✖"
                print(f"  {status} {name}({call_summary(args)})")
                if is_write and result.get("ok"):
                    write_used = True
                    actions.append(f"{name}({call_summary(args)})")

            tool_results.append({
                "role": "tool",
                "tool_call_id": call.get("id", ""),
                "content": json.dumps(result),
            })

        messages.extend(tool_results)
        iteration += 1

    # Extract final assistant text
    final_text = next(
        (m["content"] for m in reversed(messages)
         if m.get("role") == "assistant" and m.get("content")),
        "(no final text)"
    )
    print(f"\n[Omniscience done — {iteration} turn(s), {len(actions)} write(s)]")
    return {
        "summary":    final_text,
        "actions":    actions,
        "iterations": iteration,
        "write_used": write_used,
    }

# ── Entry point ───────────────────────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Omniscience CLI — Ollama tool-calling agent for Sovereign's Reach")
    parser.add_argument("task", nargs="?",
                        help="Task to perform (or omit to read from stdin)")
    parser.add_argument("--model", default=DEFAULT_MODEL,
                        help=f"Ollama model (default: {DEFAULT_MODEL})")
    parser.add_argument("--no-confirm", action="store_true",
                        help="Skip write-operation confirmations (fully autonomous)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Read-only mode: analyse and plan but make no file changes")
    args = parser.parse_args()

    task = args.task or sys.stdin.read().strip()
    if not task:
        parser.error("Provide a task as an argument or via stdin.")

    confirm_writes = not args.no_confirm
    result = run_agent(task, args.model, confirm_writes, args.dry_run)

    print("\n" + "─" * 60)
    print("SUMMARY:")
    print(result["summary"])
    if result["actions"]:
        print("\nACTIONS TAKEN:")
        for a in result["actions"]:
            print(f"  • {a}")
    print("─" * 60)

    # Machine-readable output for loop integration
    print("\n[OMNISCIENCE_RESULT]")
    print(json.dumps({k: v for k, v in result.items() if k != "summary"}, indent=2))

if __name__ == "__main__":
    main()
