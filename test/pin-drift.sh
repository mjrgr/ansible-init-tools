#!/usr/bin/env bash
# Compares every pinned <role>_version against the latest upstream release.
#
# The role list is derived, not maintained: any role whose defaults pin
# <role>_version is covered the day it lands, which is the same reason
# test/run.sh derives its pins target the same way.
#
# The upstream repo is read out of the role's own download URL in defaults, or
# out of the clis_repo it passes to resolve.yml. Roles that download from
# somewhere other than github.com need an entry in UPSTREAM below, and a role
# that has neither is reported as unknown rather than skipped — a silent skip is
# how a pin stops being watched without anyone noticing.
set -euo pipefail

cd "$(dirname "$0")/.."

declare -A UPSTREAM=(
  [kubectl]=https://dl.k8s.io/release/stable.txt
  [helm]=helm/helm
  [starship]=starship/starship
)

# Upstream tags are not a single convention: codex ships rust-v0.154.0, most ship
# v1.2.3, a few ship 1.2.3. Comparing the bare numbers is what makes them equal.
strip() { sed -e 's/^rust-v//' -e 's/^v//' <<<"$1"; }

latest_tag() {
  gh api "repos/$1/releases/latest" --jq .tag_name 2>/dev/null \
    || gh api "repos/$1/releases?per_page=1" --jq '.[0].tag_name' 2>/dev/null \
    || true
}

drift=0
unknown=0
printf '| Role | Pinned | Upstream |\n|---|---|---|\n'

for f in playbooks/roles/*/defaults/main.yml; do
  role=$(basename "$(dirname "$(dirname "$f")")")
  case "$role" in dotfiles_*) continue ;; esac
  pinned=$(sed -n "s/^${role}_version: *\"\?\([^\"]*\)\"\?/\1/p" "$f")
  [ -n "$pinned" ] || continue
  [ "$pinned" = latest ] && continue

  src="${UPSTREAM[$role]:-$(
    grep -hoE 'github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$f" | head -1 | cut -d/ -f2-3
  )}"
  # Roles whose asset lives off github (helm) still name the repo they take their
  # tag from, so fall back to that before declaring the pin unwatched.
  [ -n "$src" ] || src=$(sed -n 's/^ *clis_repo: *//p' "playbooks/roles/$role/tasks/main.yml" | head -1)
  case "$src" in
    https://*) upstream=$(curl -fsSL --retry 3 --retry-all-errors --connect-timeout 15 "$src" || true) ;;
    */*)       upstream=$(latest_tag "$src") ;;
    *)         printf '| %s | %s | **no upstream source** |\n' "$role" "$pinned"; unknown=1; continue ;;
  esac

  if [ -z "$upstream" ]; then
    printf '| %s | %s | **lookup failed** |\n' "$role" "$pinned"
    unknown=1
  elif [ "$(strip "$pinned")" != "$(strip "$upstream")" ]; then
    printf '| %s | `%s` | **`%s`** |\n' "$role" "$pinned" "$upstream"
    drift=1
  fi
done

if [ "$drift" = 0 ] && [ "$unknown" = 0 ]; then
  echo '| — | — | every pin matches upstream |'
fi
exit $(( drift || unknown ))
