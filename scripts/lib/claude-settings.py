#!/usr/bin/env python3
"""Edit ~/.claude/settings.json in place, touching only the keys this repo owns.

  hooks      SETTINGS HOOK_SCRIPT [--dry-run]   register the wezterm state hooks
  unhooks    SETTINGS HOOK_SCRIPT               take only those entries back out
  statusline SETTINGS WRAPPER                   chain herdr's statusLine wrapper

The file holds tokens, machine-local preferences and other tools' hooks next to
our keys, so it is merged, never templated: an event keeps every entry that is
not ours. Prints "changed" or "unchanged" on the last line.
"""
import json
import os
import sys
from typing import Any

EVENTS = ["UserPromptSubmit", "Stop", "Notification", "SessionStart", "SessionEnd"]
Entry = dict[str, Any]


def hooks_for(script: str) -> dict[str, Entry]:
    # SubagentStop is deliberately absent: it fires while the main agent keeps
    # working, which would turn the tab green with nothing waiting on you.
    def cmd(arg: str) -> Entry:
        return {"hooks": [{"type": "command", "command": f"{script} {arg}".rstrip()}]}
    return {
        "UserPromptSubmit": cmd("working"),
        "Stop": cmd("waiting"),
        "Notification": cmd("waiting"),
        "SessionStart": cmd(""),
        "SessionEnd": cmd(""),
    }


def is_ours(entry: Any, script: str) -> bool:
    # A hand-edited file may spell the same script with a leading ~.
    name = os.path.basename(script)
    hooks = entry.get("hooks", []) if isinstance(entry, dict) else []
    return any(name in str(h.get("command", "")) for h in hooks if isinstance(h, dict))


def with_hooks(hooks: dict[str, list[Entry]], script: str) -> dict[str, list[Entry]]:
    merged = dict(hooks)
    for event, ours in hooks_for(script).items():
        entries = list(hooks.get(event, []))
        mine = [i for i, e in enumerate(entries) if is_ours(e, script)]
        if mine:
            # In place, so an already registered file comes out byte-identical.
            entries[mine[0]] = ours
            entries = [e for i, e in enumerate(entries) if i not in mine[1:]]
        else:
            entries.append(ours)
        merged[event] = entries
    return merged


def without_hooks(hooks: dict[str, list[Entry]], script: str) -> dict[str, list[Entry]]:
    stripped = {}
    for event, entries in hooks.items():
        kept = [e for e in entries if event not in EVENTS or not is_ours(e, script)]
        if kept:
            stripped[event] = kept
    return stripped


def load(path: str) -> dict[str, Any]:
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except FileNotFoundError:
        return {}
    if not isinstance(data, dict):
        sys.exit(f"{path} did not parse as a JSON object — refusing to overwrite it")
    return data


def save(path: str, data: dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.chmod(path, 0o600)


def finish(path: str, before: dict[str, Any], after: dict[str, Any], dry_run: bool) -> None:
    if before == after:
        print("unchanged")
        return
    if not dry_run:
        save(path, after)
    print("changed")


def main(argv: list[str]) -> None:
    if len(argv) < 3:
        sys.exit(__doc__)
    action, path = argv[0], argv[1]
    dry_run = "--dry-run" in argv
    before = load(path)
    after = json.loads(json.dumps(before))

    if action == "hooks":
        after["hooks"] = with_hooks(after.get("hooks", {}), argv[2])
    elif action == "unhooks":
        stripped = without_hooks(after.get("hooks", {}), argv[2])
        if stripped:
            after["hooks"] = stripped
        else:
            after.pop("hooks", None)
    elif action == "statusline":
        wrapper = argv[2]
        status = after.get("statusLine")
        if not isinstance(status, dict):
            status = {"type": "command", "command": "ccstatusline"}
        command = status.get("command") or "ccstatusline"
        # A hand-edited file may spell the same wrapper with a leading ~.
        if os.path.basename(wrapper) not in command:
            status["command"] = f"{wrapper} {command}"
            status.setdefault("type", "command")
            after["statusLine"] = status
    else:
        sys.exit(__doc__)
    finish(path, before, after, dry_run)


if __name__ == "__main__":
    main(sys.argv[1:])
