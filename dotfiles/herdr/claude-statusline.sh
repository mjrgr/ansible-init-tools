#!/usr/bin/env bash
# Claude Code statusLine with two consumers of the same session JSON:
# herdr-agent-usage records the quota herdr's sidebar shows, then the real
# status line draws. That one is the arguments, ccstatusline by default, so a
# project whose settings.json carries its own statusLine can chain it too:
#   "command": "~/.config/herdr/claude-statusline.sh /bin/sh scripts/status-line.sh"
# agent-usage's `configure --apply` points settings.json at itself instead, so
# re-point it here after every run of that action.
set -u

input=$(cat)

# Globbed, not hard-coded: the managed checkout dir carries a hash that changes
# when the pinned ref does, and a stale path here would drop the quota silently.
bin=$(ls -d "$HOME"/.config/herdr/plugins/github/herdr-agent-usage-*/target/release/herdr-agent-usage 2>/dev/null | head -1)
if [[ -n $bin && -x $bin ]]; then
  printf '%s' "$input" \
    | HERDR_PLUGIN_STATE_DIR="$HOME/.local/state/herdr/plugins/herdr-agent-usage" \
      timeout 3 "$bin" claude-statusline >/dev/null 2>&1
fi

[[ $# -gt 0 ]] || set -- ccstatusline
printf '%s' "$input" | exec "$@"
