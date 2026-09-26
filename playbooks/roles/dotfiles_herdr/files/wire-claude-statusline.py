#!/usr/bin/env python3
"""Chain herdr's statusLine wrapper into a Claude Code settings.json.

Touches only .statusLine.command, and only when it does not already run
through the wrapper — everything else in the file (env, hooks, autoMode,
whatever Claude Code itself has written there) is left exactly as found.
Prints "changed" or "unchanged" on the last line, for Ansible's changed_when.
"""
import json
import os
import sys

settings_path, wrapper = sys.argv[1], sys.argv[2]
# The existing command may already spell this same wrapper with a leading
# "~" (as a hand-edited settings.json does) rather than the absolute path
# passed in: comparing by basename catches both without false-negatives.
wrapper_name = os.path.basename(wrapper)

try:
    with open(settings_path, encoding="utf-8") as handle:
        settings = json.load(handle)
except FileNotFoundError:
    settings = {}

status_line = settings.get("statusLine")
if not isinstance(status_line, dict):
    status_line = {"type": "command", "command": "ccstatusline"}

command = status_line.get("command") or "ccstatusline"
if wrapper_name in command:
    print("unchanged")
    sys.exit(0)

status_line["command"] = f"{wrapper} {command}"
status_line.setdefault("type", "command")
settings["statusLine"] = status_line

with open(settings_path, "w", encoding="utf-8") as handle:
    json.dump(settings, handle, indent=2)
    handle.write("\n")

print("changed")
