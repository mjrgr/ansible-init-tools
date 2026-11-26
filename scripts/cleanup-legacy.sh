#!/usr/bin/env bash
# Removes what the Ansible roles installed outside mise: the binaries under
# /usr/local/bin, the neovim/btop trees, the /opt/rust toolchain, the apt-era
# packages now pinned in mise (gh, jq, ripgrep, fd, bat, zoxide), the native
# Claude Code install. Run it after `mise run install` has proven every tool
# runs from mise — until then the old copies are the fallback.
#
# Kept on purpose, whatever the lists below say:
#   - /usr/local/bin entries that are K3s symlinks (kubectl, crictl, ctr -> k3s):
#     they belong to the K3s install, and root/systemd jobs have no mise shims;
#   - the apt `age` package: same reason (root backup jobs encrypt with it);
#   - any home path a systemd user unit or ~/.claude.json still points at
#     (e.g. a service running node from ~/.nvm): removing it breaks the next start.
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

# Files that still reference a home path ($HOME/x, %h/x as systemd writes it, or ~/x).
referenced_by() {
  local rel="${1#"$HOME"/}" f pre
  for f in "$HOME"/.config/systemd/user/*.service "$HOME/.claude.json"; do
    [[ -f "$f" ]] || continue
    for pre in "$HOME/" "%h/" "~/"; do
      if grep -qF -- "$pre$rel" "$f"; then printf '%s\n' "${f/#"$HOME"/\~}"; break; fi
    done
  done
}
# rm_path, unless something still uses the path: then report and keep it.
rm_path_unused() {
  local p="$1" refs; [[ -e "$p" || -L "$p" ]] || return 0
  refs="$(referenced_by "$p" | paste -sd, -)"
  if [[ -n "$refs" ]]; then printf '  kept %s (still used by %s)\n' "$p" "$refs"; return 1; fi
  rm_path "$p"
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
  if [[ -L "$p" && "$(readlink -f "$p")" == /usr/local/bin/k3s ]]; then
    printf '  kept %s (K3s symlink)\n' "$p"; continue
  fi
  [[ -f "$p" || -L "$p" ]] && sudo_rm_path "$p"
done

echo "== support trees"
sudo_rm_path /usr/local/share/btop
sudo_rm_path /usr/local/share/nvim
sudo_rm_path /usr/local/lib/nvim
sudo_rm_path /opt/rust

echo "== apt-era packages now pinned in mise"
if command -v dpkg-query >/dev/null; then
  # Not `age`: root/systemd jobs (no mise shims) may encrypt with it — see the header.
  pkgs="$(dpkg-query -W -f '${Package}\n' gh jq ripgrep fd-find bat zoxide 2>/dev/null || true)"
  [[ -n "$pkgs" ]] && run sudo apt-get purge -y $pkgs
  sudo_rm_path /etc/apt/sources.list.d/github-cli.list
  sudo_rm_path /etc/apt/keyrings/githubcli.gpg
  # The old bootstrap's lists: mise writes its own mise-*.sources for the same repositories,
  # and apt refuses a repository configured twice.
  for f in /etc/apt/sources.list.d/wezterm-fury.list /etc/apt/sources.list.d/vscode-msft.list \
           /etc/apt/keyrings/wezterm-fury.gpg /etc/apt/keyrings/wezterm-fury.gpg.armored \
           /etc/apt/keyrings/microsoft.gpg /etc/apt/keyrings/microsoft.asc.armored; do
    sudo_rm_path "$f"
  done
fi

echo "== native Claude Code install (claude is a mise tool now)"
# The versions tree goes only with the launcher that points into it.
rm_path_unused "$HOME/.local/bin/claude" && rm_path "$HOME/.local/share/claude"

echo "== krew and its plugins (stern, kubectl-cnpg, krelay, kubectl-whoami are mise tools now)"
rm_path "${KREW_ROOT:-$HOME/.krew}"

echo "== nvm, bun and the uv installer (node, bun, uv are mise tools now)"
rm_path_unused "${NVM_DIR:-$HOME/.nvm}" || true
rm_path_unused "${BUN_INSTALL:-$HOME/.bun}" || true
rm_path_unused "$HOME/.local/bin/uv" || true
rm_path_unused "$HOME/.local/bin/uvx" || true

echo "== kept on purpose"
echo "  apt package age (root/systemd jobs have no mise shims)"
echo "  /var/lib/docker (delete by hand once nothing in it is needed)"
echo "  ~/.cargo, ~/.rustup (mise's rust toolchain lives there now)"
