#!/usr/bin/env bash
# Removes Ansible from this machine: the system package and its repository,
# pip and pipx installs, the collections and caches, the config files. Nothing
# in this repo needs it any more. Debian/Ubuntu, Fedora/RHEL and WSL.
#
#   scripts/uninstall-ansible.sh          # dry run: lists what would go
#   scripts/uninstall-ansible.sh --yes    # does it (sudo for the system parts)
#
# Keeps ansible-lint/yamllint's siblings alone and never touches the other
# repos on the box: if Ansible is still in use elsewhere, do not run this.
set -euo pipefail

APPLY=false
[[ "${1:-}" == "--yes" ]] && APPLY=true

run() { if $APPLY; then "$@"; else printf '  would run: %s\n' "$*"; fi; }
rm_path() {
  local p="$1"; [[ -e "$p" || -L "$p" ]] || return 0
  if $APPLY; then rm -rf -- "$p"; printf '  removed %s\n' "$p"; else printf '  would remove %s\n' "$p"; fi
}
sudo_rm_path() {
  local p="$1"; [[ -e "$p" || -L "$p" ]] || return 0
  if $APPLY; then sudo rm -rf -- "$p"; printf '  removed %s\n' "$p"; else printf '  would remove %s\n' "$p"; fi
}

. /etc/os-release
case " $ID ${ID_LIKE:-} " in
  *" debian "*|*" ubuntu "*) PKG=apt ;;
  *" fedora "*|*" rhel "*|*" centos "*) PKG=dnf ;;
  *) echo "unsupported distribution: $ID" >&2; exit 1 ;;
esac
$APPLY || echo "dry run — add --yes to apply"

echo "== system package"
if [[ $PKG == apt ]]; then
  pkgs="$(dpkg-query -W -f '${Package}\n' 'ansible*' 'python3-ansible*' 2>/dev/null || true)"
  [[ -n "$pkgs" ]] && run sudo apt-get purge -y $pkgs
  # The PPA (ppa:ansible/ansible) lands as either format depending on the release.
  for f in /etc/apt/sources.list.d/ansible*; do sudo_rm_path "$f"; done
  [[ -n "$pkgs" ]] && run sudo apt-get autoremove -y
else
  pkgs="$(rpm -qa 'ansible*' 'python3-ansible*' 2>/dev/null || true)"
  [[ -n "$pkgs" ]] && run sudo dnf remove -y $pkgs
fi

echo "== pip / pipx"
for py in pip3 pip; do
  command -v "$py" >/dev/null || continue
  for p in ansible ansible-core ansible-lint ansible-compat; do
    "$py" show "$p" >/dev/null 2>&1 && run "$py" uninstall -y "$p"
  done
  break
done
if command -v pipx >/dev/null; then
  for p in ansible ansible-core ansible-lint; do
    pipx list --short 2>/dev/null | grep -q "^$p " && run pipx uninstall "$p"
  done
fi
for b in "$HOME"/.local/bin/ansible*; do rm_path "$b"; done

echo "== collections, caches, config"
rm_path "$HOME/.ansible"
rm_path "$HOME/.ansible.cfg"
rm_path "$HOME/.cache/ansible-compat"
rm_path "$HOME/.cache/ansible-lint"
sudo_rm_path /etc/ansible
rm_path /tmp/ansible-clis.log

echo "== left on PATH"
left="$(command -v ansible ansible-playbook ansible-lint 2>/dev/null || true)"
if [[ -n "$left" ]]; then printf '  %s\n' "$left"; echo "  (another install method — remove it by hand)"; else echo "  none"; fi
