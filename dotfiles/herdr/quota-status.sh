#!/usr/bin/env bash
# One line for herdr's tab bar: the account quota herdr-agent-usage last saw,
# per provider. Once, not once per agent pane — the quota is per account.
# Reads the plugin's state files only; the statusLine wrapper keeps them fresh.
# herdr strips ANSI from tab_bar_right commands, so this is plain text.
#
# Glyphs are Nerd Font Material Design Icons, the range JetBrainsMono Nerd Font
# carries and wezterm.lua already relies on; another terminal shows tofu.
set -u

state="$HOME/.local/state/herdr/plugins/herdr-agent-usage"
now=$(date +%s)
# A snapshot older than this is a session that stopped reporting, not a quota.
stale_after=$((3 * 3600))

icon_5h=$'\U000F051F'   # nf-md-timer_sand
icon_7d=$'\U000F0E17'   # nf-md-calendar_week
# nf-md-circle_outline, then circle_slice_1..8: remaining quota in eighths.
pies=($'\U000F0130' $'\U000F0A9E' $'\U000F0A9F' $'\U000F0AA0' $'\U000F0AA1' $'\U000F0AA2' $'\U000F0AA3' $'\U000F0AA4' $'\U000F0AA5')

pie() {
  printf '%s' "${pies[$(( ($1 * 8 + 50) / 100 ))]}"
}

render() {
  local label=$1 file=$2 fetched line
  [[ -r $file ]] || return
  fetched=$(jq -r '.fetched_at_unix // 0' "$file")
  line=$(jq -r '
    def cell: "\(if .kind == "five_hour" then "5h" else "7d" end) \(.remaining_percent | floor)";
    [.windows[] | select(.kind == "five_hour" or .kind == "weekly") | cell] | join(" ")' "$file")
  [[ -n $line ]] || return
  local out="$label" kind pct icon
  while read -r kind pct; do
    [[ -n ${kind:-} ]] || continue
    [[ $kind == 5h ]] && icon=$icon_5h || icon=$icon_7d
    out+="  $icon $(pie "$pct")"
    (( pct < 100 )) && out+=" $pct"
  done < <(printf '%s\n' $line | paste - -)
  (( now - fetched > stale_after )) && out+="?"
  printf '%s' "$out"
}

claude=$(render Claude "$state/claude-statusline.json")
codex=$(render Codex "$state/codex-app-server.json")
printf '%s\n' "${claude}${claude:+${codex:+  ·  }}${codex}"
