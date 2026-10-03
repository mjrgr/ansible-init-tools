#!/usr/bin/env bash
# Bumps every pinned <role>_version that upstream has moved past, then
# refreshes its checksums. Same upstream-detection as pin-drift.sh: keep the
# UPSTREAM map and strip() in sync with it for roles whose asset isn't hosted
# on github.com.
#
#   ./test/bump-pins.sh          bump every stale pin
#   ./test/bump-pins.sh kind yq  limit to these roles
#
# Prints what it changed, then leaves the diff staged in the working tree for
# review — it does not commit.
set -euo pipefail

cd "$(dirname "$0")/.."

declare -A UPSTREAM=(
  [kubectl]=https://dl.k8s.io/release/stable.txt
  [helm]=helm/helm
  [starship]=starship/starship
  [cargo]=rust-lang/rustup
)

strip() { sed -e 's/^rust-v//' -e 's/^v//' <<<"$1"; }

latest_tag() {
  local out
  if out=$(gh api "repos/$1/releases/latest" --jq .tag_name 2>/dev/null) && [ -n "$out" ] && [ "$out" != null ]; then
    echo "$out"; return
  fi
  if out=$(gh api "repos/$1/releases?per_page=1" --jq '.[0].tag_name' 2>/dev/null) && [ -n "$out" ] && [ "$out" != null ]; then
    echo "$out"; return
  fi
  if out=$(gh api "repos/$1/tags?per_page=1" --jq '.[0].name' 2>/dev/null) && [ -n "$out" ] && [ "$out" != null ]; then
    echo "$out"; return
  fi
}

wanted=("$@")
in_wanted() {
  [ "${#wanted[@]}" -eq 0 ] && return 0
  local r
  for r in "${wanted[@]}"; do [ "$r" = "$1" ] && return 0; done
  return 1
}

bumped=()
for f in playbooks/roles/*/defaults/main.yml; do
  role=$(basename "$(dirname "$(dirname "$f")")")
  in_wanted "$role" || continue

  pinned=$(sed -n "s/^${role}_version: *\"\?\([^\"]*\)\"\?/\1/p" "$f")
  [ -n "$pinned" ] || continue
  [ "$pinned" = latest ] && continue

  src="${UPSTREAM[$role]:-$(
    grep -hoE 'github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' "$f" | head -1 | cut -d/ -f2-3
  )}"
  [ -n "$src" ] || src=$(sed -n 's/^ *clis_repo: *//p' "playbooks/roles/$role/tasks/main.yml" | head -1)
  if [ -z "$src" ]; then
    echo "skip $role: no upstream source"
    continue
  fi

  case "$src" in
    https://*) upstream=$(curl -fsSL --retry 3 --retry-all-errors --connect-timeout 15 "$src" || true) ;;
    */*)       upstream=$(latest_tag "$src") ;;
    *)         upstream="" ;;
  esac
  if [ -z "$upstream" ]; then
    echo "skip $role: upstream lookup failed"
    continue
  fi

  if [ "$(strip "$pinned")" = "$(strip "$upstream")" ]; then
    continue
  fi

  # Keep whichever prefix style the pin already used: v1.2.3, rust-v1.2.3 (the
  # tag strips back off to plain semver), or bare 1.2.3.
  prefix=$(sed -E 's/^((rust-v|v)?).*/\1/' <<<"$pinned")
  new="${prefix}$(strip "$upstream")"

  echo "bump $role: $pinned -> $new"
  if grep -q "^${role}_version: \"" "$f"; then
    sed -i "s/^${role}_version: \".*\"/${role}_version: \"${new}\"/" "$f"
  else
    sed -i "s/^${role}_version: .*/${role}_version: ${new}/" "$f"
  fi
  bumped+=("$role")
done

if [ "${#bumped[@]}" -eq 0 ]; then
  echo "every pin already matches upstream"
  exit 0
fi

echo
echo "==> regenerating checksums for: ${bumped[*]}"
./test/checksums.py "${bumped[@]}"

echo
echo "Bumped: ${bumped[*]}"
echo "Review the diff (git diff), then run 'make test-pins' before committing."
