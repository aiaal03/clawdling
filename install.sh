#!/bin/zsh
# Installs Clawdling: builds the app, wires the Claude Code hooks, starts it at login.
# Safe to run again: it updates in place and keeps your pet.
set -e
cd "$(dirname "$0")"
DATA="$HOME/.clawdling"
APPS="$HOME/Applications"
LABEL="io.github.clawdling"

./build.sh
mkdir -p "$DATA" "$APPS"
cp feed.py tg.py "$DATA/"
chmod +x "$DATA/feed.py" "$DATA/tg.py"

pkill -x Clawdling 2>/dev/null || true
rm -rf "$APPS/Clawdling.app"
cp -R build/Clawdling.app "$APPS/"

# Claude Code hooks -> ~/.clawdling/feed.py (async, so they never slow Claude down)
mkdir -p "$HOME/.claude"
[ -f "$HOME/.claude/settings.json" ] || echo '{}' > "$HOME/.claude/settings.json"
cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.bak-clawdling"
/usr/bin/python3 - "$DATA/feed.py" <<'PY'
import json, os, sys
p = os.path.expanduser("~/.claude/settings.json")
s = json.load(open(p))
cmd = f'/usr/bin/python3 "{sys.argv[1]}"'
hooks = s.setdefault("hooks", {})
# drop earlier Clawdling hooks (any path), then add the current ones
for ev, groups in list(hooks.items()):
    for g in groups:
        g["hooks"] = [h for h in g.get("hooks", []) if "clawdling" not in h.get("command", "").lower()]
    hooks[ev] = [g for g in groups if g.get("hooks")]
# (event, matcher): food from prompts, tools and finished turns; the magnifier on approvals and questions
for ev, matcher in (("UserPromptSubmit", None), ("PostToolUse", None), ("Stop", None),
                    ("PermissionRequest", None), ("Notification", "permission_prompt"),
                    ("PreToolUse", "AskUserQuestion")):
    g = {"hooks": [{"type": "command", "command": cmd, "timeout": 5, "async": True}]}
    if matcher:
        g = {"matcher": matcher, **g}
    hooks.setdefault(ev, []).append(g)
json.dump(s, open(p, "w"), indent=2, ensure_ascii=False)
PY

# start at login
PL="$HOME/Library/LaunchAgents/$LABEL.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PL" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$APPS/Clawdling.app</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PL

open "$APPS/Clawdling.app"
echo ""
echo "🥚 Clawdling is running. Work in Claude Code to hatch your egg."
echo "   Right-click the pet for its menu. Uninstall: ./uninstall.sh"
