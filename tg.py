#!/usr/bin/env python3
"""Optional Telegram alerts: `tg.py "text"` sends one message.

Config: ~/.clawdling/telegram.env with two lines
    BOT_TOKEN=123456:ABC...
    CHAT_ID=123456789
No file, no alerts.
"""
import os, sys, urllib.parse, urllib.request

d = os.environ.get("CLAWDLING_DIR") or os.path.expanduser("~/.clawdling")
cfg = {}
try:
    for line in open(os.path.join(d, "telegram.env")):
        if "=" in line and not line.strip().startswith("#"):
            k, v = line.strip().split("=", 1)
            cfg[k.strip()] = v.strip().strip('"')
except FileNotFoundError:
    sys.exit(0)
if cfg.get("BOT_TOKEN") and cfg.get("CHAT_ID") and len(sys.argv) > 1:
    data = urllib.parse.urlencode({"chat_id": cfg["CHAT_ID"], "text": sys.argv[1][:4000]}).encode()
    urllib.request.urlopen(f"https://api.telegram.org/bot{cfg['BOT_TOKEN']}/sendMessage", data, timeout=10)
