# shellcheck shell=bash
# Shared by the mise file tasks under mise/tasks/. Source it, never run it.
#
# Every task reports what it changed with `changed`, and nothing otherwise: the
# container test asserts a second run prints no "changed:" line at all, which is
# the idempotence check the Ansible `changed=0` summary used to give.
set -euo pipefail

# The task is reached through ~/.config/mise (a symlink into the repo) or
# directly from the clone; readlink -f lands on the clone either way.
REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../.." && pwd)"
# shellcheck disable=SC2034  # read by the tasks that source this file
DOTFILES="$REPO/dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup"
STAMP="$(date +%Y%m%dT%H%M%S)"

say()     { printf '%s\n' "$*"; }
changed() { printf 'changed: %s\n' "$*"; }
die()     { printf 'error: %s\n' "$*" >&2; exit 1; }

# mode only on the directory this call creates: under WSL ~/.kube is often a
# drvfs mount where chmod returns EPERM, and an existing directory that works
# must not fail the run for nothing.
ensure_dir() {
  local d="$1"
  [[ -d "$d" ]] && return 0
  mkdir -p "$d" && chmod 0755 "$d"
  changed "mkdir $d"
}

# dest -> src symlink. A real pre-existing file is moved to the backup
# directory; a stale symlink carries no user data and is replaced silently.
link_dotfile() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || die "missing source $src"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    return 0
  fi
  if [[ -e "$dest" && ! -L "$dest" ]]; then
    mkdir -p "$BACKUP_DIR"
    mv -- "$dest" "$BACKUP_DIR/$(basename "$dest").$STAMP"
    changed "backed up $dest"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -sfn -- "$src" "$dest"
  changed "link $dest -> $src"
}

# Seeds a local override from its template; never overwrites what is there.
copy_template() {
  local src="$1" dest="$2" mode="$3"
  [[ -e "$dest" ]] && return 0
  install -m "$mode" -- "$src" "$dest"
  changed "seeded $dest"
}

# Clones once, never updates: the plugin managers (omz, herdr) own upgrades.
# GIT_CONFIG_GLOBAL=/dev/null: the deployed ~/.gitconfig may already be linked
# (tasks run in parallel) and carry settings this host's git does not know —
# merge.conflictStyle=zdiff3 is fatal on the git 2.34 Ubuntu 22.04 ships.
clone_once() {
  local url="$1" dest="$2"
  [[ -d "$dest/.git" ]] && return 0
  GIT_CONFIG_GLOBAL=/dev/null git clone --quiet --depth 1 -- "$url" "$dest"
  changed "cloned $url"
}

# Downloads to a temp file and swaps it in only when the content differs, so an
# unchanged upstream file is a no-op and a changed one is reported.
fetch_if_changed() {
  local url="$1" dest="$2" mode="${3:-0644}" tmp
  tmp="$(mktemp)"
  curl -fsSL --retry 5 --retry-all-errors --retry-max-time 120 --connect-timeout 15 -o "$tmp" "$url"
  # sha256sum, not cmp: a minimal Fedora image ships no diffutils.
  if [[ -f "$dest" ]] && [[ "$(sha256sum < "$tmp")" == "$(sha256sum < "$dest")" ]]; then
    rm -f "$tmp"; return 0
  fi
  install -m "$mode" -- "$tmp" "$dest"; rm -f "$tmp"
  changed "fetched $dest"
}

have() { command -v "$1" >/dev/null 2>&1; }
