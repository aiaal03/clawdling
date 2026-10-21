#!/usr/bin/env python3
"""Claude Code hook -> Clawdling. Turns a hook event into one line of ~/.clawdling/events.jsonl.

Food: prompts, tool calls and finished turns. "ask" means Claude needs an approval or an
answer, so the pet pulls out its magnifier and goes looking for you.
"""
import json, os, sys, time

try:
    h = json.load(sys.stdin)
except Exception:
    h = {}

ev = h.get("hook_event_name", "")
tool = h.get("tool_name", "") or ""
k = None
if ev == "PermissionRequest" \
        or (ev == "Notification" and (h.get("notification_type") == "permission_prompt"
                                   or "permission" in (h.get("message") or "").lower())) \
        or (ev == "PreToolUse" and tool == "AskUserQuestion"):
    k = "ask"
elif ev == "UserPromptSubmit":
    k = "prompt"
elif ev == "Stop":
    k = "done"
elif ev == "PostToolUse":
    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        k = "edit"
    elif tool == "Bash":
        k = "bash"
    elif tool in ("WebSearch", "WebFetch") or "browser" in tool.lower() or "chrome" in tool.lower():
        k = "web"
    elif tool in ("Agent", "Task", "Workflow"):
        k = "agent"
    else:
        k = "other"

if k:
    d = os.environ.get("CLAWDLING_DIR") or os.path.expanduser("~/.clawdling")
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "events.jsonl"), "a") as f:
        f.write(json.dumps({"t": time.time(), "k": k}) + "\n")
