#!/usr/bin/env bash
# Publishes the herd's agent counts where wezterm.lua can read them for free.
#
# The reader runs on wezterm's GUI thread once a second. Asking herdr from there
# would mean wsl.exe on the Windows laptop — ~100 ms of frozen UI per tick. This
# inverts the cost: the crossing happens here, off that thread, and the GUI only
# opens a local file. `herdr api snapshot` over the unix socket costs ~8 ms, so
# polling is cheaper than any of the alternatives (`herdr agent wait` needs a
# target and cannot watch the herd as a whole).
set -uo pipefail

interval="${HERD_PUBLISH_INTERVAL:-2}"

# LOCALAPPDATA under WSL so the Windows GUI reads an NTFS path; ~/.cache on a
# native Linux box. wezterm.lua branches the same way.
win_local="/mnt/c/Users/${USER}/AppData/Local"
if [[ -d $win_local ]]; then out="$win_local/herd-status"; else out="$HOME/.cache/herd-status"; fi
mkdir -p "$(dirname "$out")"

while :; do
  line=$(herdr api snapshot 2>/dev/null | jq -r '
    [.result.snapshot.agents[].agent_status] as $s
    | [ ($s | map(select(. == "working")) | length),
        ($s | map(select(. == "blocked")) | length),
        ($s | map(select(. == "done"))    | length) ]
    | join(" ")' 2>/dev/null) || line=''
  # Written whole or not at all: the reader must never catch a half-flushed file.
  printf '%s\n' "$line" > "$out.tmp" && mv -f "$out.tmp" "$out"
  sleep "$interval"
done
