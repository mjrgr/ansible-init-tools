#!/usr/bin/env bash
# The one thing `mise bootstrap` cannot do: put the pinned mise binary on the box.
# Everything else — packages, repositories, dotfiles, login shell, tools — is
# declared in mise/config.toml and applied by `mise bootstrap` (make setup).
#
#   scripts/bootstrap.sh          # install or replace /usr/local/bin/mise at the pinned version
#
# Asks for sudo itself: it re-executes through `sudo env` so the proxy variables
# survive, which a plain `sudo scripts/bootstrap.sh` strips before curl.
set -euo pipefail

MISE_VERSION="v2026.11.14"
# From SHASUMS256.txt on the release page; `make bump-mise` moves the three lines.
MISE_SHA256_X64="6fa596291e9758106f761fea4f8e7fac6c3e7ff4714d5c0b9a76e16068db14f6"
MISE_SHA256_ARM64="7bd3b2d5ffff077a7662ba186c09600e5b40c1eee9df0c264ed67642ce0a8698"
MISE_DEST=/usr/local/bin/mise

[[ $# -eq 0 ]] || { sed -n '2,9p' "$0"; exit 2; }

if [[ $(id -u) -ne 0 ]]; then
  keep=()
  for v in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
    [[ -n "${!v:-}" ]] && keep+=("$v=${!v}")
  done
  exec sudo env "${keep[@]}" "$(readlink -f "$0")"
fi

case "$(uname -m)" in
  x86_64)  ARCH=x64;   SHA="$MISE_SHA256_X64" ;;
  aarch64) ARCH=arm64; SHA="$MISE_SHA256_ARM64" ;;
  *) echo "unsupported architecture: $(uname -m) (x86_64 and aarch64 only)" >&2; exit 1 ;;
esac
# A bare image has no curl: the one package this script installs itself.
if ! command -v curl >/dev/null; then
  if command -v apt-get >/dev/null; then DEBIAN_FRONTEND=noninteractive apt-get update -q && apt-get install -y -q --no-install-recommends curl ca-certificates
  else dnf install -y -q curl ca-certificates; fi
fi

# The release binary, pinned and checksummed, not `curl https://mise.run | sh`: that
# script picks its own version. System-wide so `wsl.exe -- mise` and the systemd user
# unit find it without a login shell.
installed="$("$MISE_DEST" --version 2>/dev/null | awk '{print $1}' || true)"
if [[ "v$installed" == "$MISE_VERSION" ]]; then
  echo "mise $MISE_VERSION already installed"
  exit 0
fi
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 5 --retry-all-errors --retry-max-time 120 -o "$tmp" \
  "https://github.com/jdx/mise/releases/download/$MISE_VERSION/mise-$MISE_VERSION-linux-$ARCH"
echo "$SHA  $tmp" | sha256sum -c --quiet - || { echo "mise: checksum mismatch" >&2; exit 1; }
install -m 0755 "$tmp" "$MISE_DEST"
echo "installed $("$MISE_DEST" --version)"
