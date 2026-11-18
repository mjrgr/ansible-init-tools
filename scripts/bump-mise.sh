#!/usr/bin/env bash
# Move the mise pin in scripts/bootstrap.sh to the latest release (or $1, e.g.
# v2026.11.9): version and both sha256 from the release's SHASUMS256.txt.
# Then `mise run bootstrap` installs it. Not `mise self-update`: that one skips
# the checksum and, under a plain sudo, the proxy.
set -euo pipefail

REPO_URL=https://github.com/jdx/mise
SCRIPT="$(dirname "$(readlink -f "$0")")/bootstrap.sh"

version="${1:-$(curl -fsSL --retry 3 -o /dev/null -w '%{url_effective}' "$REPO_URL/releases/latest" | sed 's#.*/##')}"
[[ $version == v* ]] || { echo "bad version: $version" >&2; exit 1; }
current="$(sed -n 's/^MISE_VERSION="\(.*\)"$/\1/p' "$SCRIPT")"
if [[ $version == "$current" ]]; then echo "mise already pinned to $current"; exit 0; fi

sums="$(curl -fsSL --retry 3 "$REPO_URL/releases/download/$version/SHASUMS256.txt")"
x64="$(awk -v f="./mise-$version-linux-x64" '$2 == f {print $1}' <<<"$sums")"
arm64="$(awk -v f="./mise-$version-linux-arm64" '$2 == f {print $1}' <<<"$sums")"
[[ -n $x64 && -n $arm64 ]] || { echo "$version: linux-x64/arm64 missing from SHASUMS256.txt" >&2; exit 1; }

sed -i -e "s/^MISE_VERSION=.*/MISE_VERSION=\"$version\"/" \
       -e "s/^MISE_SHA256_X64=.*/MISE_SHA256_X64=\"$x64\"/" \
       -e "s/^MISE_SHA256_ARM64=.*/MISE_SHA256_ARM64=\"$arm64\"/" "$SCRIPT"
echo "mise $current -> $version in $SCRIPT; now: mise run bootstrap (or make bootstrap)"
