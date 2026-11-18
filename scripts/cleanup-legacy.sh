#!/usr/bin/env bash
# Removes what the Ansible roles installed outside mise: the binaries under
# /usr/local/bin, the neovim/btop trees, the /opt/rust toolchain, the apt-era
# packages now pinned in mise (gh, jq, ripgrep, fd, bat, zoxide), the native
# Claude Code install. Run it after `mise run install` has proven every tool
# runs from mise — until then the old copies are the fallback.
#
#   scripts/cleanup-legacy.sh          # dry run
#   scripts/cleanup-legacy.sh --yes    # apply (sudo for /usr/local, /opt, apt)
set -euo pipefail

APPLY=false
[[ "${1:-}" == "--yes" ]] && APPLY=true
$APPLY || echo "dry run — add --yes to apply"

run() { if $APPLY; then "$@"; else printf '  would run: %s\n' "$*"; fi; }
sudo_rm_path() {
  local p="$1"; [[ -e "$p" || -L "$p" ]] || return 0
  if $APPLY; then sudo rm -rf -- "$p"; printf '  removed %s\n' "$p"; else printf '  would remove %s\n' "$p"; fi
}
rm_path() {
  local p="$1"; [[ -e "$p" || -L "$p" ]] || return 0
  if $APPLY; then rm -rf -- "$p"; printf '  removed %s\n' "$p"; else printf '  would remove %s\n' "$p"; fi
}

# Every binary install_clis.yml placed in /usr/local/bin (mise is not one of them).
bins=(kubectl helm kind kwok kwokctl k9s popeye sofka argo9s helmfile nerdctl crictl argocd
      kubectx kubens kubie cilium hubble kyverno vcluster cmctl k0sctl telepresence
      cloud-provider-kind helm-schema tofu trivy cosign oras dive ko yq sops certigo
      starship glow vhs gitlogue herdr fzf btop eza delta lazygit nvim codex codex-code-mode-host
      cargo rustc fd bat kubectl-krew)

echo "== /usr/local/bin binaries (regular files and symlinks only)"
for b in "${bins[@]}"; do
  p="/usr/local/bin/$b"
  [[ -f "$p" || -L "$p" ]] && sudo_rm_path "$p"
done

echo "== support trees"
sudo_rm_path /usr/local/share/btop
sudo_rm_path /usr/local/share/nvim
sudo_rm_path /usr/local/lib/nvim
sudo_rm_path /opt/rust

echo "== apt-era packages now pinned in mise"
if command -v dpkg-query >/dev/null; then
  pkgs="$(dpkg-query -W -f '${Package}\n' gh jq ripgrep fd-find bat zoxide age 2>/dev/null || true)"
  [[ -n "$pkgs" ]] && run sudo apt-get purge -y $pkgs
  sudo_rm_path /etc/apt/sources.list.d/github-cli.list
  sudo_rm_path /etc/apt/keyrings/githubcli.gpg
fi

echo "== native Claude Code install (claude is a mise tool now)"
rm_path "$HOME/.local/bin/claude"
rm_path "$HOME/.local/share/claude"

echo "== krew's own copy of itself (kubectl-krew is a mise tool now)"
rm_path "${KREW_ROOT:-$HOME/.krew}/store/krew"
rm_path "${KREW_ROOT:-$HOME/.krew}/receipts/krew.yaml"
rm_path "${KREW_ROOT:-$HOME/.krew}/bin/kubectl-krew"

echo "== kept on purpose"
echo "  /var/lib/docker (delete by hand once nothing in it is needed)"
echo "  ~/.cargo, ~/.rustup (mise's rust toolchain lives there now)"
