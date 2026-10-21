#!/bin/zsh
# Removes Clawdling: the app, its Claude Code hooks and the login item.
# Your pet's save (~/.clawdling) stays unless you pass --purge.
set -e
pkill -x Clawdling 2>/dev/null || true
rm -rf "$HOME/Applications/Clawdling.app"
rm -f "$HOME/Library/LaunchAgents/io.github.clawdling.plist"
if [ -f "$HOME/.claude/settings.json" ]; then
  /usr/bin/python3 - <<'PY'
import json, os
p = os.path.expanduser("~/.claude/settings.json")
s = json.load(open(p))
hooks = s.get("hooks", {})
for ev, groups in list(hooks.items()):
    for g in groups:
        g["hooks"] = [h for h in g.get("hooks", []) if "clawdling" not in h.get("command", "").lower()]
    hooks[ev] = [g for g in groups if g.get("hooks")]
    if not hooks[ev]:
        del hooks[ev]
json.dump(s, open(p, "w"), indent=2, ensure_ascii=False)
PY
fi
if [ "$1" = "--purge" ]; then
  rm -rf "$HOME/.clawdling"
  echo "Clawdling and its save are gone. 🪦"
else
  echo "Clawdling removed. The save is kept in ~/.clawdling (use --purge to delete it)."
fi
