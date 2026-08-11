#!/usr/bin/env bash
# Run the playbooks against a throwaway Ubuntu container.
#
#   ./test/run.sh dotfiles        # full dotfiles.yml, twice, asserts idempotence
#   ./test/run.sh clis [role]     # install_clis.yml, optionally a single role
#   ./test/run.sh rollback        # deploy then roll back, asserts the restore
#   ./test/run.sh pins            # every pinned tool version still installs
#   ./test/run.sh wezterm         # installs wezterm and parses the versioned config
#   ./test/run.sh shell           # interactive shell in the test bed
#
# The repo is mounted read-only: any attempt by a playbook to write into it fails
# loudly instead of silently polluting the working tree.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:-dotfiles}"

# UBUNTU_VERSION=22.04 ./test/run.sh dotfiles  — the apt ansible-core differs per
# LTS and they do not behave the same; CI runs the suite across both.
UBUNTU_VERSION="${UBUNTU_VERSION:-26.04}"
IMAGE="ansible-init-tools-test:${UBUNTU_VERSION}"

# The playbooks reach out to github/vendor endpoints; carry the host proxy through.
PROXY_ENV=()
for v in http_proxy https_proxy no_proxy HTTP_PROXY HTTPS_PROXY NO_PROXY; do
  [[ -n "${!v:-}" ]] && PROXY_ENV+=(-e "$v=${!v}")
done

echo "==> building $IMAGE"
docker build -q -t "$IMAGE" --build-arg "UBUNTU_VERSION=$UBUNTU_VERSION" \
  "${PROXY_ENV[@]/#-e/--build-arg}" "$REPO/test" >/dev/null

# bash -c, not -lc: a login shell runs ~/.bash_logout on the way out, and Ubuntu's
# ends with `[ -x /usr/bin/clear_console ] && ...` which returns 1 when that binary
# is absent. Under set -e that status overrides an explicit `exit 0`, turning a
# passing target into a CI failure. The container PATH already covers /usr/local/bin.
run() {
  docker run --rm \
    -v "$REPO:/repo:ro" \
    "${PROXY_ENV[@]}" \
    "$IMAGE" bash -c "$1"
}

case "$TARGET" in
  dotfiles)
    # Both runs must happen inside the SAME container: `docker run --rm` starts
    # from a pristine $HOME every time, which would make any playbook look
    # non-idempotent.
    run '
      set -e
      PB="ansible-playbook /repo/playbooks/dotfiles.yml -c local -i localhost,"

      echo "==> run 1 (fresh $HOME)"
      $PB >/tmp/r1.log 2>&1 || { tail -30 /tmp/r1.log; exit 1; }
      grep "localhost  " /tmp/r1.log

      echo
      echo "==> run 2 — must report changed=0"
      $PB >/tmp/r2.log 2>&1 || { tail -30 /tmp/r2.log; exit 1; }
      grep "localhost  " /tmp/r2.log
      grep -q "changed=0 " /tmp/r2.log || { echo "IDEMPOTENCE FAILED"; exit 1; }
      echo "    idempotence OK"

      echo
      echo "==> deployed layout"
      for f in ~/.zshrc ~/.zshenv ~/.tmux.conf ~/.gitconfig \
               ~/.config/starship.toml ~/.config/zsh/wezterm.zsh \
               ~/.config/wezterm/wezterm.lua ~/.kube/k8s-clusters.sh \
               ~/.zshenv.local ~/.zshrc.local ~/.gitconfig.local; do
        printf "    %-30s %s\n" "${f#$HOME/}" "$(readlink -f "$f" 2>/dev/null || echo MISSING)"
      done

      echo
      echo "==> the deployed shell actually works"
      zsh -n ~/.zshrc && echo "    zsh -n: OK"
      zsh -i -c "
        print -r -- \"    k alias        : \$(alias k)\"
        print -r -- \"    plugins        : \${#plugins} declared\"
        print -r -- \"    _PROXY default : \${_PROXY:-<empty — proxy is opt-in>}\"
        print -r -- \"    KUBECONFIG     : \${KUBECONFIG:-<empty>}\"
      " 2>&1 | grep -v "can.t change option"

      echo
      echo "==> the Nerd Font is installed and visible to fontconfig"
      n=$(ls ~/.local/share/fonts/JetBrainsMono*.ttf 2>/dev/null | wc -l)
      echo "    font files: $n"
      [ "$n" -gt 0 ] || { echo "    no font installed — failed"; exit 1; }
      fc-list | grep -qi "JetBrainsMono.*Nerd" \
        && echo "    fc-list sees it: $(fc-list | grep -ci "JetBrainsMono.*Nerd") faces" \
        || { echo "    fontconfig does not see the font — failed"; exit 1; }

      echo
      echo "==> preflight refuses to run when a prerequisite is missing"
      if $PB -e "{\"dotfiles_requirements\":[\"no-such-binary\"]}" >/tmp/r3.log 2>&1; then
        echo "    NOT ENFORCED — expected a failure"; exit 1
      else
        grep -o "Missing command(s):[^\"]*" /tmp/r3.log | head -1 | sed "s/^/    /"
      fi

      echo
      echo "==> repo untouched (mounted read-only)"
      touch /repo/_probe 2>/dev/null && { echo "    WRITEABLE — unexpected"; exit 1; } || echo "    read-only confirmed"
    '
    ;;
  clis)
    ROLE="${2:-}"
    ONLY=""
    [[ -n "$ROLE" ]] && ONLY="-e install_only=$ROLE"
    echo "==> install_clis.yml ${ROLE:+(role: $ROLE)}"
    echo "    Note: daemons (docker, podman) install but do not start in a container."
    run "ansible-playbook /repo/playbooks/install_clis.yml -c local -i localhost, $ONLY 2>&1 | tail -30"
    ;;
  rollback)
    # Seeds real files first, so the restore path is actually exercised and not
    # just the symlink removal.
    run '
      set -e
      PB="ansible-playbook /repo/playbooks/dotfiles.yml -c local -i localhost,"
      RB="ansible-playbook /repo/playbooks/dotfiles_rollback.yml -c local -i localhost,"

      echo "==> seeding pre-existing files"
      mkdir -p ~/.config
      echo "ORIGINAL ZSHRC"    > ~/.zshrc
      echo "ORIGINAL STARSHIP" > ~/.config/starship.toml

      echo "==> deploy"
      $PB >/tmp/d.log 2>&1 || { tail -30 /tmp/d.log; exit 1; }
      printf "    ~/.zshrc                is a symlink: %s\n" "$([ -L ~/.zshrc ] && echo yes || echo NO)"
      printf "    ~/.config/starship.toml is a symlink: %s\n" "$([ -L ~/.config/starship.toml ] && echo yes || echo NO)"

      echo
      echo "==> rollback"
      $RB >/tmp/rb.log 2>&1 || { tail -30 /tmp/rb.log; exit 1; }

      echo "    after rollback:"
      for f in ~/.zshrc ~/.config/starship.toml; do
        if [ -L "$f" ]; then echo "      ${f#$HOME/}: STILL A SYMLINK — failed"; exit 1
        elif [ -f "$f" ]; then echo "      ${f#$HOME/}: restored -> $(head -1 "$f")"
        else echo "      ${f#$HOME/}: MISSING — failed"; exit 1; fi
      done

      # The original content must come back, and land in the right directory.
      grep -q "ORIGINAL ZSHRC"    ~/.zshrc                || { echo "      wrong content in ~/.zshrc"; exit 1; }
      grep -q "ORIGINAL STARSHIP" ~/.config/starship.toml || { echo "      wrong content in ~/.config/starship.toml"; exit 1; }
      [ -e ~/starship.toml ] && { echo "      starship.toml restored to \$HOME instead of ~/.config"; exit 1; }

      echo
      echo "==> local overrides survive the rollback"
      for f in ~/.zshenv.local ~/.zshrc.local ~/.gitconfig.local; do
        printf "      %-20s %s\n" "${f#$HOME/}" "$([ -f "$f" ] && echo kept || echo LOST)"
      done
      echo
      echo "    rollback OK"
    '
    ;;
  pins)
    # Nothing upstream watches the pinned versions in the role defaults —
    # dependabot has no ecosystem for them. This is what catches a tag that was
    # yanked or an asset URL that changed shape.
    run '
      set -e
      PB="ansible-playbook /repo/playbooks/install_clis.yml -c local -i localhost,"
      fail=0
      for role in kubectl helm kind kwok k9s krew helmfile nerdctl crictl yq sops starship; do
        want=$(sed -n "s/^${role}_version: *\"\?\([^\"]*\)\"\?/\1/p" \
               /repo/playbooks/roles/$role/defaults/main.yml)
        if $PB -e install_only=$role >/tmp/p.log 2>&1; then
          printf "  %-9s pinned=%-10s installed\n" "$role" "$want"
        else
          printf "  %-9s pinned=%-10s INSTALL FAILED\n" "$role" "$want"
          tail -12 /tmp/p.log | sed "s/^/      /"
          fail=1
        fi
      done
      exit $fail
    '
    ;;
  wezterm)
    # Installs wezterm, then parses the versioned config with the real binary.
    # show-keys renders the key table without needing a GUI or a display.
    run '
      set -e
      echo "==> installing wezterm"
      ansible-playbook /repo/playbooks/install_clis.yml -c local -i localhost, \
        -e install_only=wezterm >/tmp/wt.log 2>&1 || {
          echo "    install failed:"; tail -40 /tmp/wt.log | sed "s/^/      /"; exit 1; }
      echo "    $(wezterm --version)"
      echo
      echo "==> parsing dotfiles/wezterm/wezterm.lua"
      if wezterm --config-file /repo/dotfiles/wezterm/wezterm.lua show-keys >/tmp/keys.txt 2>/tmp/err.txt; then
        echo "    PARSE OK — $(grep -c . /tmp/keys.txt) lines of key table"
        grep -iE "error|warn" /tmp/err.txt | head -5 | sed "s/^/    WARN: /" || true
      else
        echo "    PARSE FAILED:"; sed "s/^/    /" /tmp/err.txt | head -20; exit 1
      fi
    '
    ;;
  shell)
    docker run --rm -it -v "$REPO:/repo:ro" "${PROXY_ENV[@]}" "$IMAGE" bash
    ;;
  *)
    echo "unknown target: $TARGET (expected: dotfiles | clis | rollback | pins | wezterm | shell)" >&2
    exit 2
    ;;
esac
