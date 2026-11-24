#!/usr/bin/env bash
# Everything that needs root, on Debian/Ubuntu, Fedora/RHEL and WSL: the base
# packages, podman, WezTerm, VS Code, and the pinned mise binary. Everything
# else is mise's job (mise/config.toml) and runs as the user.
#
#   scripts/bootstrap.sh                      # all of it (first run: nothing else is installed yet)
#   scripts/bootstrap.sh --skip podman,wezterm,vscode
#   scripts/bootstrap.sh --upgrade            # also move the packages it owns to their latest
#   mise run bootstrap -- --upgrade           # same, once mise is in place (= make upgrade)
#
# Asks for sudo itself: it re-executes through `sudo env` so the proxy variables
# survive, which a plain `sudo scripts/bootstrap.sh` strips before curl and apt.
#
# Idempotent: packages go through the package manager, mise is reinstalled only
# when the installed version differs from the pin. --upgrade touches only the
# packages listed in this file, never the rest of the system.
set -euo pipefail

MISE_VERSION="v2026.11.14"
# From SHASUMS256.txt on the release page; bump both lines with the version.
MISE_SHA256_X64="6fa596291e9758106f761fea4f8e7fac6c3e7ff4714d5c0b9a76e16068db14f6"
MISE_SHA256_ARM64="7bd3b2d5ffff077a7662ba186c09600e5b40c1eee9df0c264ed67642ce0a8698"
MISE_DEST=/usr/local/bin/mise

ARGS=("$@")
SKIP=""; UPGRADE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip) SKIP=",$2,"; shift 2 ;;
    --skip=*) SKIP=",${1#--skip=},"; shift ;;
    --upgrade) UPGRADE=true; shift ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done
skipped() { [[ "$SKIP" == *",$1,"* ]]; }

if [[ $(id -u) -ne 0 ]]; then
  keep=()
  for v in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
    [[ -n "${!v:-}" ]] && keep+=("$v=${!v}")
  done
  exec sudo env "${keep[@]}" "$(readlink -f "$0")" "${ARGS[@]}"
fi

say() { printf '==> %s\n' "$*"; }

# ── Platform ────────────────────────────────────────────────────────────────
case "$(uname -m)" in
  x86_64)  ARCH=x64;   DEB_ARCH=amd64 ;;
  aarch64) ARCH=arm64; DEB_ARCH=arm64 ;;
  *) echo "unsupported architecture: $(uname -m) (x86_64 and aarch64 only)" >&2; exit 1 ;;
esac

. /etc/os-release
case " $ID ${ID_LIKE:-} " in
  *" debian "*|*" ubuntu "*) PKG=apt ;;
  *" fedora "*|*" rhel "*|*" centos "*) PKG=dnf ;;
  *) echo "unsupported distribution: $ID (Debian/Ubuntu or Fedora/RHEL family only)" >&2; exit 1 ;;
esac
WSL=false; grep -qi microsoft /proc/version 2>/dev/null && WSL=true
say "$PRETTY_NAME, $(uname -m), $PKG$($WSL && echo ', WSL')"

export DEBIAN_FRONTEND=noninteractive
# Every package goes through here, so --upgrade knows exactly what it owns.
# --no-upgrade: a plain run leaves installed packages where they are; moving them is --upgrade's job.
OWNED=()
pkg_install() {
  OWNED+=("$@")
  if [[ $PKG == apt ]]; then apt-get install -y --no-install-recommends --no-upgrade "$@"; else dnf install -y "$@"; fi
}

# ── Base packages ───────────────────────────────────────────────────────────
# What mise and the dotfiles tasks need from the system: a shell, VCS, fetch
# tools, gpg for the apt keyrings below, unzip for the Nerd Font, fontconfig,
# python3 for the settings.json merges, and what cargo needs to build clauth and
# the herdr plugins: a C/C++ toolchain and OpenSSL via pkg-config (memex falls
# back to a source build where its prebuilt binary does not run, as on 22.04).
# Every CLI tool is in mise/config.toml.
say "base packages"
if [[ $PKG == apt ]]; then
  apt-get update
  pkg_install git curl wget gnupg unzip zsh fontconfig ca-certificates python3 build-essential pkg-config libssl-dev
else
  pkg_install git curl wget gnupg2 unzip zsh fontconfig ca-certificates python3 make gcc gcc-c++ pkgconf-pkg-config openssl-devel
  # chsh moved to a sub-package on Fedora.
  command -v chsh >/dev/null || pkg_install util-linux-user
fi

# ── Leftovers from the apt-era roles ────────────────────────────────────────
# A HashiCorp source under a different keyring path leaves apt with two
# Signed-By lines for one URL, and apt then refuses the whole sources.list.d.
if [[ $PKG == apt ]]; then
  rm -f /etc/apt/sources.list.d/hashicorp.list /etc/apt/keyrings/hashicorp.gpg /etc/apt/keyrings/hashicorp.gpg.armored
  install -d -m 0755 /etc/apt/keyrings
fi

# ── podman (docker CLI via podman-docker, no daemon, no docker0) ────────────
if ! skipped podman; then
  say "podman"
  docker_pkgs=(docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io docker-buildx-plugin docker-compose-plugin)
  if [[ $PKG == apt ]]; then
    # Not purged: /var/lib/docker (images, volumes) stays until removed by hand.
    apt-get remove -y "${docker_pkgs[@]}" 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/docker.list /etc/apt/keyrings/docker.gpg /etc/apt/keyrings/docker.gpg.armored
    pkg_install podman podman-docker
    # Ubuntu ships no search registry: `docker run mcp/grafana` fails on short names.
    install -d -m 0755 /etc/containers/registries.conf.d
    printf 'unqualified-search-registries = ["docker.io"]\n' > /etc/containers/registries.conf.d/10-unqualified-search.conf
  else
    dnf remove -y "${docker_pkgs[@]}" 2>/dev/null || true
    rm -f /etc/yum.repos.d/docker-ce.repo
    pkg_install podman podman-docker
  fi
  # dockerd leaves docker0 up on stop; its 172.17.0.0/16 route can swallow an SSH session.
  [[ -e /sys/class/net/docker0 ]] && ip link delete docker0 || true
  # Silences the shim's "Emulate Docker CLI using podman" banner.
  [[ -e /etc/containers/nodocker ]] || : > /etc/containers/nodocker
fi

# ── WezTerm (GUI app: distro packages lag, so the official repositories) ────
if ! skipped wezterm; then
  say "wezterm"
  if [[ $PKG == apt ]]; then
    if [[ ! -f /etc/apt/keyrings/wezterm-fury.gpg ]]; then
      curl -fsSL --retry 3 https://apt.fury.io/wez/gpg.key | gpg --yes --dearmor -o /etc/apt/keyrings/wezterm-fury.gpg
      chmod 0644 /etc/apt/keyrings/wezterm-fury.gpg
    fi
    echo 'deb [signed-by=/etc/apt/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' > /etc/apt/sources.list.d/wezterm-fury.list
    apt-get update && pkg_install wezterm
  elif [[ $ID == fedora ]]; then
    # Upstream's documented route for Fedora; no stable rpm repo exists.
    # Not owned: a provides name, which dnf upgrade would reject.
    dnf install -y 'dnf-command(copr)' 2>/dev/null || dnf install -y dnf-plugins-core
    dnf copr enable -y wezfurlong/wezterm-nightly
    pkg_install wezterm
  else
    echo "    wezterm: no repository for $ID — install the rpm from https://wezterm.org/install/linux.html" >&2
  fi
fi

# ── VS Code (Microsoft's repository; the snap and the .deb self-update) ─────
if ! skipped vscode; then
  say "vscode"
  if [[ $PKG == apt ]]; then
    if [[ ! -f /etc/apt/keyrings/microsoft.gpg ]]; then
      curl -fsSL --retry 3 https://packages.microsoft.com/keys/microsoft.asc | gpg --yes --dearmor -o /etc/apt/keyrings/microsoft.gpg
      chmod 0644 /etc/apt/keyrings/microsoft.gpg
    fi
    # The code package's postinst adds its own copy of the repo under another
    # keyring path; the debconf question is how to opt out before it unpacks.
    echo "code code/add-microsoft-repo boolean false" | debconf-set-selections
    rm -f /etc/apt/sources.list.d/vscode.list /etc/apt/sources.list.d/vscode.sources
    echo "deb [arch=$DEB_ARCH signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode-msft.list
    apt-get update && pkg_install code
  else
    rpm --import https://packages.microsoft.com/keys/microsoft.asc
    # yumrepos/vscode: the yumrepos/code path from older docs answers 404 now.
    cat > /etc/yum.repos.d/vscode.repo <<'REPO'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
REPO
    pkg_install code
  fi
fi

# ── mise ────────────────────────────────────────────────────────────────────
# The release binary, pinned and checksummed, not `curl https://mise.run | sh`:
# that script picks its own version. System-wide so `wsl.exe -- mise` and the
# systemd user unit find it without a login shell.
say "mise $MISE_VERSION"
installed="$("$MISE_DEST" --version 2>/dev/null | awk '{print $1}' || true)"
if [[ "v$installed" == "$MISE_VERSION" ]]; then
  echo "    already installed"
else
  sha="$([[ $ARCH == x64 ]] && echo "$MISE_SHA256_X64" || echo "$MISE_SHA256_ARM64")"
  tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
  curl -fsSL --retry 5 --retry-all-errors --retry-max-time 120 -o "$tmp" \
    "https://github.com/jdx/mise/releases/download/$MISE_VERSION/mise-$MISE_VERSION-linux-$ARCH"
  echo "$sha  $tmp" | sha256sum -c --quiet - || { echo "mise: checksum mismatch" >&2; exit 1; }
  install -m 0755 "$tmp" "$MISE_DEST"
  echo "    installed $("$MISE_DEST" --version 2>/dev/null)"
fi

# ── --upgrade: the owned packages only ──────────────────────────────────────
if $UPGRADE; then
  say "upgrade: ${#OWNED[@]} owned packages"
  if [[ $PKG == apt ]]; then
    apt-get install -y --no-install-recommends --only-upgrade "${OWNED[@]}"
  else
    dnf upgrade -y "${OWNED[@]}"
  fi
fi

cat <<MSG

Done. As your user, from the clone (make setup runs these for you):
  mise trust mise/config.toml
  mise run install          # every pinned tool
  mise run dotfiles         # symlinks, oh-my-zsh, fonts, herdr, login shell
Later: mise run bootstrap -- --upgrade, or make upgrade for the tools as well.
$($WSL && echo "WSL: the herd-publish user unit needs systemd=true in /etc/wsl.conf (then wsl --shutdown).")
MSG
