#!/usr/bin/env bash
# Run the bootstrap, the tool install and the dotfiles tasks against a
# throwaway container.
#
#   ./test/run.sh dotfiles        # `mise bootstrap` twice (no tools), asserts idempotence and what landed
#   ./test/run.sh clis            # mise binary + `mise install` twice + `mise bootstrap packages upgrade`, asserts every tool runs
#   ./test/run.sh rollback        # deploy then roll back, asserts the restore
#   ./test/run.sh wezterm         # installs wezterm and parses the versioned config
#   ./test/run.sh shell           # interactive shell in the test bed
#
# BASE_IMAGE=ubuntu:22.04 (or fedora:43) switches the distro; CI runs all three.
#
# The repo is bind-mounted read-only and copied inside the container: mise
# writes mise.lock next to its config, and `git status` on the copy is what
# proves a run changed nothing in the tree.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-dotfiles}"
BASE_IMAGE="${BASE_IMAGE:-ubuntu:26.04}"
IMAGE="ansible-init-tools-test:${BASE_IMAGE//[:\/]/-}"

# The runs reach github/vendor endpoints; carry the host proxy and the GitHub
# token through (the github backend asks api.github.com for release assets).
PASS_ENV=()
for v in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY MISE_GITHUB_TOKEN GITHUB_TOKEN DOTFILES_HERDR_PLUGINS; do
  [[ -n "${!v:-}" ]] && PASS_ENV+=(-e "$v=${!v}")
done
BUILD_ARGS=()
for v in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
  [[ -n "${!v:-}" ]] && BUILD_ARGS+=(--build-arg "$v=${!v}")
done

echo "==> building $IMAGE"
docker build -q -t "$IMAGE" --build-arg "BASE_IMAGE=$BASE_IMAGE" "${BUILD_ARGS[@]}" "$REPO/test" >/dev/null

# bash -c, not -lc: a login shell runs ~/.bash_logout on the way out, and
# Ubuntu's returns 1 when clear_console is absent, which under set -e turns a
# passing target into a failure.
run() {
  local cache=()
  if [[ -n "${CLAUTH_CACHE:-}" ]]; then
    local dir="${CLAUTH_CACHE/#\~/$HOME}"  # a workflow env value is not tilde-expanded
    mkdir -p "$dir"; cache=(-v "$dir:/home/tester/.local/share/mise/installs/clauth")
  fi
  docker run --rm -v "$REPO:/repo:ro" "${cache[@]}" "${PASS_ENV[@]}" "$IMAGE" bash -c "$1"
}

# Snapshot the working tree into a writable copy and stage it, so the worktree
# column of `git status` afterwards lists exactly what the run wrote.
PRELUDE='
set -e
cp -a /repo/. ~/repo/ && cd ~/repo
# A git worktree carries a .git file pointing outside the mount: a fresh repo serves the snapshot as well.
[ -d .git ] || { rm -f .git; git init -q; }
git -c user.name=t -c user.email=t@t add -A >/dev/null
tree_untouched() {
  local dirty; dirty=$(git -C ~/repo status --porcelain | grep -E "^.[^ ]" || true)
  if [ -n "$dirty" ]; then echo "    TREE MODIFIED:"; echo "$dirty" | sed "s/^/      /"; return 1; fi
  echo "    tree untouched"
}
export PATH="$HOME/.local/share/mise/shims:$PATH"
# docker creates the mount path as root: hand the tree to the bench user before mise writes in it.
[ ! -d ~/.local/share/mise/installs/clauth ] || sudo chown -R "$(id -u):$(id -g)" ~/.local
# No auto-install before a task: `mise run rollback` would first fetch every tool.
export MISE_YES=1 MISE_TASK_RUN_AUTO_INSTALL=false
./scripts/bootstrap.sh >/tmp/b.log 2>&1 || { tail -30 /tmp/b.log; exit 1; }
mise trust -q mise/config.toml
# Global config from the start, as on a host: the pypi/npm lock paths in mise.lock
# are written as locks/ for the global config and .mise/locks/ for a project one.
mkdir -p ~/.config && ln -sfn ~/repo/mise ~/.config/mise
# No user manager in a container: the services part is skipped and the bootstrap
# task guards the unit itself. chsh: the bootstrap task does it through sudo.
BOOTSTRAP="mise bootstrap --skip services,user"
'

case "$TARGET" in
  dotfiles)
    # Both runs in the SAME container: a fresh one would make anything look idempotent.
    # --skip tools: the clis target covers them; the bootstrap task then skips what needs them.
    run "$PRELUDE"'
      mise --version | sed "s/^/    mise /"
      echo "==> run 1 (fresh $HOME): $BOOTSTRAP --skip tools"
      $BOOTSTRAP --skip tools >/tmp/r1.log 2>&1 || { tail -40 /tmp/r1.log; exit 1; }
      printf "    mise: %s part(s) applied, task: %s change(s)\n" \
        "$(grep -cE "^mise [a-z ]+: (added|installed|applied|created|cloned)" /tmp/r1.log || true)" "$(grep -c "^changed: " /tmp/r1.log || true)"

      echo
      echo "==> run 2 — must change nothing"
      $BOOTSTRAP --skip tools >/tmp/r2.log 2>&1 || { tail -40 /tmp/r2.log; exit 1; }
      if grep -E "^mise [a-z ]+: (added|installed|applied|created|cloned)|^changed: " /tmp/r2.log; then echo "IDEMPOTENCE FAILED"; exit 1; fi
      echo "    idempotence OK"

      echo
      echo "==> deployed layout"
      for f in ~/.zshrc ~/.zshenv ~/.tmux.conf ~/.gitconfig ~/.config/mise \
               ~/.config/starship.toml ~/.config/zsh/wezterm.zsh \
               ~/.config/wezterm/wezterm.lua ~/.config/btop/btop.conf ~/.config/nvim \
               ~/.kube/k8s-clusters.sh ~/.config/krelay/patch-hardened.json \
               ~/.zshenv.local ~/.zshrc.local ~/.gitconfig.local; do
        printf "    %-32s %s\n" "${f#$HOME/}" "$(readlink -f "$f" 2>/dev/null || echo MISSING)"
        [ -e "$f" ] || exit 1
      done

      echo
      echo "==> the deployed shell actually works"
      zsh -n ~/.zshrc && echo "    zsh -n: OK"
      zsh -i -c "
        print -r -- \"    k alias        : \$(alias k)\"
        print -r -- \"    plugins        : \${#plugins} declared\"
        print -r -- \"    _PROXY default : \${_PROXY:-<empty — proxy is opt-in>}\"
        print -r -- \"    mise on PATH   : \$(command -v mise)\"
      " 2>&1 | grep -v "can.t change option"

      echo
      echo "==> mise config is global now"
      (cd / && mise tasks ls | grep -q "^bootstrap " && echo "    tasks visible from /")
      echo "==> mise bootstrap status"
      mise bootstrap status 2>&1 | grep -vE "^\s*$" | tail -12 | sed "s/^/    /"

      echo
      echo "==> zsh is the login shell"
      sh=$(getent passwd "$(id -un)" | cut -d: -f7)
      echo "    passwd shell: $sh"
      case "$sh" in */zsh) ;; *) echo "    chsh did not happen — failed"; exit 1 ;; esac

      echo
      echo "==> the Nerd Font is installed and visible to fontconfig"
      n=$(ls ~/.local/share/fonts/JetBrainsMono*.ttf 2>/dev/null | wc -l)
      [ "$n" -gt 0 ] || { echo "    no font installed — failed"; exit 1; }
      fc-list | grep -qi "JetBrainsMono.*Nerd" && echo "    fc-list sees $(fc-list | grep -ci "JetBrainsMono.*Nerd") faces" \
        || { echo "    fontconfig does not see the font — failed"; exit 1; }

      echo
      echo "==> Claude Code hooks registered"
      python3 -c "import json; h=json.load(open(\"$HOME/.claude/settings.json\"))[\"hooks\"]; assert set(h) >= {\"UserPromptSubmit\",\"Stop\",\"Notification\",\"SessionStart\",\"SessionEnd\"}; print(\"    5 events\")"

      echo
      echo "==> repo tree"
      tree_untouched
    '
    ;;
  clis)
    run "$PRELUDE"'
      echo "==> system packages (mise bootstrap --only packages; daemons install but do not start in a container)"
      mise bootstrap --only packages >/tmp/p.log 2>&1 || { tail -40 /tmp/p.log; exit 1; }
      grep -E "^mise (apt|dnf):" /tmp/p.log | sed "s/^/    /"
      for c in podman docker mise; do printf "    %-8s %s\n" "$c" "$(command -v $c || echo MISSING)"; done

      echo
      echo "==> run 1: mise run install (every pinned tool, from mise.lock)"
      mise run install >/tmp/c1.log 2>&1 || { tail -60 /tmp/c1.log; exit 1; }
      printf "    installed: %s tool(s)\n" "$(mise ls --json | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")"
      grep "^changed: " /tmp/c1.log | sed "s/^/    /" | head -12

      echo
      echo "==> run 2 — must reinstall nothing"
      mise run install >/tmp/c2.log 2>&1 || { tail -40 /tmp/c2.log; exit 1; }
      if grep -qE "installed [1-9][0-9]* tool|^changed: " /tmp/c2.log; then
        echo "    REINSTALLED ON A SECOND RUN:"; grep -E "installed|^changed: " /tmp/c2.log | sed "s/^/      /"; exit 1
      fi
      echo "    nothing reinstalled"

      echo
      echo "==> mise bootstrap packages upgrade (nothing to move right after an install)"
      mise bootstrap packages upgrade >/tmp/b2.log 2>&1 || { tail -40 /tmp/b2.log; exit 1; }
      if grep -qE "^mise (apt|dnf): (installed|upgraded)" /tmp/b2.log; then
        echo "    UPGRADED SOMETHING:"; grep -E "^mise (apt|dnf):" /tmp/b2.log | sed "s/^/      /"; exit 1
      fi
      echo "    nothing to upgrade"

      echo
      echo "==> mise run check (every tool answers, lock audited, mise doctor clean)"
      CHECK_VERBOSE=1 mise run check 2>&1 | sed "s/^/    /"
      [ "${PIPESTATUS[0]}" = 0 ] || exit 1

      echo
      echo "==> repo tree (mise.lock must be stable)"
      tree_untouched
    '
    ;;
  rollback)
    # Seeds a real file first: mise refuses to replace it unless told to, which is the
    # point; --force-dotfiles is the explicit opt-in on a box with history.
    run "$PRELUDE"'
      echo "==> seeding a pre-existing file"
      echo "ORIGINAL ZSHRC" > ~/.zshrc
      echo "==> deploy must refuse the conflict"
      if $BOOTSTRAP --skip tools >/tmp/d0.log 2>&1; then echo "    deployed over a real file — failed"; exit 1; fi
      grep -iE "conflict|force" /tmp/d0.log | head -2 | sed "s/^/    /"
      grep -q "ORIGINAL ZSHRC" ~/.zshrc && echo "    ~/.zshrc untouched"

      echo "==> deploy with --force-dotfiles"
      $BOOTSTRAP --skip tools --force-dotfiles >/tmp/d.log 2>&1 || { tail -30 /tmp/d.log; exit 1; }
      for f in ~/.zshrc ~/.config/starship.toml ~/.config/mise; do
        printf "    %-26s is a symlink: %s\n" "${f#$HOME/}" "$([ -L "$f" ] && echo yes || echo NO)"
      done

      echo
      echo "==> rollback"
      mise run rollback >/tmp/rb.log 2>&1 || { tail -30 /tmp/rb.log; exit 1; }
      for f in ~/.zshrc ~/.config/starship.toml ~/.config/mise ~/.config/btop/themes; do
        if [ -e "$f" ] || [ -L "$f" ]; then echo "      ${f#$HOME/}: STILL THERE — failed"; exit 1; fi
      done
      echo "      every entry unlinked"
      python3 -c "import json; d=json.load(open(\"$HOME/.claude/settings.json\")); assert not set(d.get(\"hooks\", {})) & {\"Stop\",\"SessionStart\"}" \
        && echo "      Claude hooks un-registered"

      echo
      echo "==> local overrides survive the rollback"
      for f in ~/.zshenv.local ~/.zshrc.local ~/.gitconfig.local; do
        printf "      %-20s %s\n" "${f#$HOME/}" "$([ -f "$f" ] && echo kept || echo LOST)"
      done
      echo
      echo "    rollback OK"
    '
    ;;
  wezterm)
    # Installs wezterm, then parses the versioned config with the real binary.
    run "$PRELUDE"'
      echo "==> installing wezterm (mise bootstrap --only packages)"
      mise bootstrap --only packages >/tmp/wt.log 2>&1 || { tail -40 /tmp/wt.log; exit 1; }
      echo "    $(wezterm --version)"
      echo "==> parsing dotfiles/wezterm/wezterm.lua"
      if wezterm --config-file ~/repo/dotfiles/wezterm/wezterm.lua show-keys >/tmp/keys.txt 2>/tmp/err.txt; then
        echo "    PARSE OK — $(grep -c . /tmp/keys.txt) lines of key table"
        grep -iE "error|warn" /tmp/err.txt | head -5 | sed "s/^/    WARN: /" || true
      else
        echo "    PARSE FAILED:"; sed "s/^/    /" /tmp/err.txt | head -20; exit 1
      fi
    '
    ;;
  shell)
    docker run --rm -it -v "$REPO:/repo:ro" "${PASS_ENV[@]}" "$IMAGE" bash
    ;;
  *)
    echo "unknown target: $TARGET (expected: dotfiles | clis | rollback | wezterm | shell)" >&2
    exit 2
    ;;
esac
