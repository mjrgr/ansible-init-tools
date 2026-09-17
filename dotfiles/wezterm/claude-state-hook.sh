#!/usr/bin/env bash
# Claude Code hook: publishes claude_state (working|waiting|'') to the WezTerm tab
# bar as an OSC 1337 user var. The pane's tty comes from the `claude` zsh wrapper
# (CLAUDE_STATE_TTY); /dev/tty is the fallback and is absent when claude spawns
# hooks in their own session or runs headless (-p, SDK), where this stays silent.
state=${1:-}
cat >/dev/null
target=${CLAUDE_STATE_TTY:-/dev/tty}
log() { [[ -n ${CLAUDE_STATE_DEBUG:-} ]] && printf '%s %s %s\n' "$(date +%T)" "$state" "$*" >>"${TMPDIR:-/tmp}/claude-state-hook.log"; }
{ exec 3>>"$target"; } 2>/dev/null || { log "open failed: $target"; exit 0; }
printf '\033]1337;SetUserVar=claude_state=%s\007' "$(printf '%s' "$state" | base64 | tr -d '\n')" >&3
log "sent to $target"
exit 0
