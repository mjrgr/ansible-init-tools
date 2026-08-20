
# 📥 Ansible init Tools 🧰

An Ansible project for installing a collection of CLI tools **and deploying personal
dotfiles** on **Ubuntu / Debian**.

### Features
- ✅ Self-contained (no external Galaxy roles required)
- ✅ Idempotent — a re-run installs nothing it already installed, and reports `changed=0`
- ✅ Every tool pins to a concrete version, or tracks `latest` by default
- ✅ Dotfiles deployed as symlinks into the repo — edit in `$HOME`, `git status` sees it
- ✅ Nothing site-specific is versioned: secrets, proxies and host names stay in local override files
- ✅ Secret scanning in CI and in a pre-commit hook
- ✅ Tested against a throwaway container, not just against the machine that wrote it

## Two playbooks, two privilege scopes

| | `install_clis.yml` | `dotfiles.yml` |
|---|---|---|
| Privileges | `become: true` (sudo) | `become: false` |
| Writes to | `/usr/local/bin`, `/etc/apt` | `$HOME`, `$HOME/.config` |
| Purpose | system-wide tooling | per-user configuration |

## Included CLIs / utilities
- kubectl, helm, kind, kwok, k9s, krew, helmfile
- docker, podman, nerdctl, crictl
- opentofu
- yq, jq
- gh
- sops, age
- starship, wezterm, vscode
- btop, lazygit
- eza, ripgrep, fd, bat, zoxide, delta
- git, make, curl, wget, gnupg, unzip, fontconfig

WezTerm comes from the official apt repository (`apt.fury.io/wez`): the distro
packages lag several releases behind. Same reasoning for VS Code and
`packages.microsoft.com` — with one extra step, since the `code` package installs
its own copy of that repository from its postinst. The role preseeds
`code/add-microsoft-repo=false` so apt is not left with two `Signed-By` lines for
the same URL, which makes it refuse the whole of `sources.list.d`.

The Rust CLIs are split by how fast they move. `rust_clis` takes ripgrep, fd, bat
and zoxide from apt in one batch, and shims `fdfind`/`batcat` back to `fd`/`bat` —
Debian renames them to avoid a clash with fdclone and bacula. eza and delta get
their own roles and pinned binaries: the apt versions are a year or more behind
and predate options the deployed configs use.

## Managed dotfiles

| Group | Deployed to |
|---|---|
| `zsh` | `~/.zshrc`, `~/.zshenv`, oh-my-zsh + 3 external plugins, `~/.config/zsh/wezterm.zsh`, `~/.kube/k8s-clusters.sh` |
| `starship` | `~/.config/starship.toml` |
| `fonts` | JetBrainsMono Nerd Font into `~/.local/share/fonts` |
| `claude` | Claude Code into `~/.local/share/claude`, symlinked at `~/.local/bin/claude` |
| `tmux` | `~/.tmux.conf` |
| `git` | `~/.gitconfig` |
| `wezterm` | `~/.config/wezterm/wezterm.lua` |
| `btop` | `~/.config/btop/btop.conf` |

Each one is a symlink into `dotfiles/` in this repo, so an edit made in `$HOME` shows
up in `git status` with no copy-back step. The `fonts` group is the exception — a font
is installed, not linked.

The Nerd Font is not cosmetic: `starship.toml` and `wezterm.lua` use Private Use Area
glyphs, and without the font the prompt and the tab bar render tofu.

The zsh and WezTerm configs work together: `~/.config/zsh/wezterm.zsh` emits OSC 133
semantic zones and publishes the current kubectl context as a user var, which
`wezterm.lua` renders in the tab title and right status bar. In the tab title it turns
matrix green while `k9s` is running, so the color means "pointed at this cluster
right now" rather than just "what kubectl would target".

The color scheme follows the desktop light/dark preference *live*, not only at
startup: `window-config-reloaded` re-derives it and pushes titlebar and tab-bar
colors along with it, which a bare `color_scheme` override would leave behind.

A background tab marks itself with an amber ● once it has produced output you have
not looked at, and the bell — silent since `audible_bell` was disabled — now flashes
the cursor.

A tab also shows a green 󰚩 while a Claude Code session runs in any of its panes.
Detection is two-layered: reading the pane's foreground process needs no shell
cooperation, but only recognises the native binary at
`~/.local/share/claude/versions/<semver>` (an npm install runs under `node` and
stays invisible), and it cannot see into a pane at all when the WezTerm GUI and
the pane's shell are on opposite sides of a WSL boundary — see below. The
`claude` zsh wrapper (`~/.zshrc`) backs it up by setting a `claude_active` user
var over OSC 1337, which rides the terminal byte stream instead of the process
tree and works in both cases.

A blue 󱃾 marks a tab running `k9s`. The process check is blind under WSL for the
same reason, so the fallback here is the pane title: oh-my-zsh's `termsupport`
sets it to the running command, and a title crosses the WSL boundary because it
travels in the byte stream. No shell wrapper needed. The kube-context suffix
drops its own glyph while that icon shows, so the tab never carries the same
symbol twice.

An orange ● marks a tab where a command is running. WezTerm's own
`has_unseen_output` looks like the obvious source and is not: it means "bytes
arrived since you last focused this pane", and an invisible OSC 133 sequence or
a background redraw sets it just as well as real work does, so it stays lit on
idle tabs until you visit them. A `busy` user var set in `preexec` and cleared
in `precmd` tracks the shell instead of the byte stream. The dot is hidden when
the claude or k9s icon already shows — those say the same thing — and on the
active tab, where the command is in front of you. A pane with no zsh prompt (an
ssh session, a `docker exec`) never lights it.

The Windows GUI reads its config over `\\wsl.localhost`, which WezTerm does not
watch — config edits do **not** auto-reload there. `Ctrl+Shift+R` forces it
(`Ctrl+Alt+R` is bound too, but Ctrl+Alt is AltGr on a FR layout and never
reaches the binding).

### Windows + WSL

`dotfiles/wezterm/wezterm.lua` drives both a native Linux desktop and a
Windows+WSL laptop from one file, branching on `wezterm.target_triple` for the
handful of settings that only make sense on one side (`wsl_domains`,
`default_prog`, `enable_wayland`). On Windows, `wezterm-gui.exe` reads its
config from the Windows profile (`%USERPROFILE%\.wezterm.lua`), never from
WSL's `$HOME` — this repo's ansible roles have no reach there. Point it at the
repo file once, from an elevated-or-Developer-Mode PowerShell/cmd so `mklink`
doesn't need admin:

```
mklink C:\Users\<you>\.wezterm.lua \\wsl.localhost\<Distro>\home\<you>\workspace\...\ansible-init-tools\dotfiles\wezterm\wezterm.lua
```

Building that command from a WSL bash one-liner is a known trap: double-quoted
bash strings collapse `\\` to `\`, silently turning the UNC path into a bogus
`C:\wsl.localhost\...`. Use single quotes for the argument, or type it directly
in PowerShell.

## Usage

`make help` lists everything. The common paths:

```bash
make install     # CLI tools (sudo) — installs only what is missing
make upgrade     # re-run every installer and upgrade in place
make dotfiles    # deploy the dotfiles (no sudo)
make rollback    # remove the symlinks, restore the backups
make test        # deploy in a container, assert idempotence
make lint        # yamllint + ansible-lint + syntax check
make scan        # scan the tree and history for secrets
make hooks       # enable the pre-commit secret scan
```

The underlying commands, when you need finer control:

```bash
ansible-playbook playbooks/install_clis.yml -c local --ask-become-pass
ansible-playbook playbooks/dotfiles.yml -c local
```

One tool or one group, either by variable or by tag:

```bash
ansible-playbook playbooks/install_clis.yml -e install_only=kubectl -c local -K
ansible-playbook playbooks/install_clis.yml --tags kubectl,helm -c local -K
ansible-playbook playbooks/dotfiles.yml --tags starship -c local
```

Useful variables:

| Variable | Default | Purpose |
|---|---|---|
| `clis_state` | `present` | `latest` re-runs every installer and upgrades |
| `<tool>_version` | `latest` | pin one tool, e.g. `-e kubectl_version=v1.30.0` |
| `install_only` | *(unset)* | install a single tool |
| `docker_add_user_to_group` | `true` | add the invoking user to the `docker` group |
| `dotfiles_only` | *(unset)* | deploy a single group |
| `dotfiles_set_default_shell` | `false` | `chsh` to zsh — needs `--ask-become-pass` |

## The docker group

`docker_add_user_to_group` defaults to `true`, so the account that runs the playbook
lands in the `docker` group and `docker` works without `sudo`.

**That membership is equivalent to root on the host.** The daemon runs as root and will
bind-mount any path into a container on request, so anyone in the group can read or
write anything. It is enabled because the alternative is `sudo` before every docker
command; disable it where that trade does not hold:

```bash
ansible-playbook playbooks/install_clis.yml -c local -K -e docker_add_user_to_group=false
```

The group takes effect at the next login — `newgrp docker` in the meantime.

The user is resolved from `SUDO_USER`, not `ansible_user_id`: the play declares
`become: true`, so facts are gathered as root and `ansible_user_id` would say `root`.

## Reproducibility

Every tool installed from a release binary is pinned to a concrete version in
`playbooks/roles/<tool>/defaults/main.yml`, so two machines provisioned months apart
get the same binary. The list is not repeated here, or in the test suite: both derive
it from the `<role>_version` defaults, so a role added later is covered without
anyone remembering to register it.

Override per run, or edit the default to bump:

```bash
ansible-playbook playbooks/install_clis.yml -c local -K -e kubectl_version=v1.30.0
ansible-playbook playbooks/install_clis.yml -c local -K -e kubectl_version=latest
```

A re-run is idempotent: each role probes the installed version first and skips when it
already matches. Moving a pin is detected and reinstalls. `clis_state=latest` is the
explicit opt-in to upgrade everything past its pin — the same semantics as
`state: present` versus `state: latest` on the apt module.

Not pinned, and why:

| Tool | Reason |
|---|---|
| docker, gh, podman, jq, wezterm, vscode, rust_clis | installed from apt repositories, which track whatever apt has at install time |
| claude | self-updating, and installed per user by the dotfiles play; pick a train with `dotfiles_claude_channel` |

**Dependabot does not watch these pins** — no ecosystem understands versions living in
Ansible defaults. It covers the GitHub Actions tags and the test image only. What
guards the pins is `make test-pins`, which installs every pinned version in a
container and fails on a yanked tag or a changed asset URL. It runs in CI.

## Bootstrap on a new machine

```bash
git clone <this-repo> && cd ansible-init-tools

# 1. Tools (sudo)
ansible-playbook playbooks/install_clis.yml -c local --ask-become-pass

# 2. Dotfiles + set zsh as the login shell
ansible-playbook playbooks/dotfiles.yml -c local \
  -e dotfiles_set_default_shell=true --ask-become-pass

# 3. Fill in the local, non-versioned files
$EDITOR ~/.zshenv.local     # secrets, tokens, proxy (mode 0600)
$EDITOR ~/.gitconfig.local  # git identity, credential helper
```

The repo must stay in place after deployment: `$HOME` symlinks point into it.

## Local overrides

**Nothing site-specific is versioned** — no secret, no proxy, no internal host name.
The versioned files carry structure and defaults that are safe anywhere; everything
else lives in gitignored files, seeded from `*.example` templates and never
overwritten by a re-run:

| File | Contents | Sourced |
|---|---|---|
| `~/.zshenv.local` | tokens, proxy | by **every** zsh shell, before `.zshrc` |
| `~/.zshrc.local` | interactive aliases and overrides | at the end of `.zshrc` |
| `~/.gitconfig.local` | git identity, credential helper | via `[include]` from `.gitconfig` |

Secrets go in `~/.zshenv.local`, not `~/.zshrc.local`: a process spawned outside an
interactive shell never reads `.zshrc`, so an export placed there would be invisible
to it.

The HTTP proxy is opt-in. `.zshrc` exports `http_proxy`/`https_proxy` only when
`_PROXY` is set in `~/.zshenv.local` — a wrong default would break every outbound
call on a network that has none.

Where a password store is available, prefer indirection over literals — see the
commented `pass` example in `.zshenv.local.example`.

## Testing in Docker

The playbooks can be exercised against a throwaway Ubuntu container, which is the
only honest way to check what happens on a machine that has never been touched:

```bash
./test/run.sh dotfiles        # full dotfiles.yml, twice, asserts idempotence
./test/run.sh clis [role]     # install_clis.yml, optionally a single role
./test/run.sh rollback        # deploy then roll back, asserts the restore
./test/run.sh pins            # every pinned tool version still installs
./test/run.sh wezterm         # installs wezterm and parses the versioned config
./test/run.sh shell           # interactive shell in the test bed
```

The repo is bind-mounted **read-only**, so a playbook that tried to write into the
working tree would fail loudly instead of polluting it silently. The host proxy
variables are carried through to the build and the run.

The base image is selectable, and CI runs the suite across both LTS releases:

```bash
UBUNTU_VERSION=22.04 ./test/run.sh dotfiles
```

This is not cosmetic. 22.04 ships ansible-core 2.12 and 26.04 ships 2.16, and they do
not behave the same — an `include_role` whose `apply.tags` referenced `item` worked on
2.16 and failed on 2.12, because `item` resolves inside the included role, against
that role's own loop. Only the older release surfaced it.

What `dotfiles` asserts:

- run 1 completes on a pristine `$HOME`
- run 2 reports `changed=0` — both runs happen in the **same** container, since a
  fresh one would make any playbook look idempotent
- every symlink and local template lands where expected
- the deployed `.zshrc` parses and an interactive zsh loads it
- the preflight refuses to run when a prerequisite is missing
- nothing was written into the repo

The playbooks run as the unprivileged user and escalate per task, which is how the
README tells you to run them. Running the whole playbook under `sudo -E` instead
leaves a root-owned `~/.ansible/tmp` behind that then breaks the unprivileged
dotfiles play.

The container runs `bash -c`, not `bash -lc`: a login shell executes `~/.bash_logout`
on the way out, and Ubuntu's ends with a test that returns 1 when `clear_console` is
absent — under `set -e` that status silently overrides an explicit `exit 0` and turns a
passing target into a failure.

Caveats: daemons (docker, podman) install but do not start in a container,
and `dotfiles_set_default_shell` is left off so `chsh` is never exercised.

## Backups and rollback

The first deployment moves any pre-existing real file to
`~/.dotfiles-backup/<name>.<timestamp>` before symlinking. Stale symlinks are replaced
silently — they carry no user data. Nothing is ever deleted.

To undo a deployment:

```bash
make rollback
```

It removes only the symlinks that point into this repo — anything else in those paths
predates the deploy and is left alone — then restores the most recent backup of each
file. The backups stay on disk, and the three `*.local` files are never touched.

## Secret scanning

The token that leaks is the one nobody scanned for. Two gates:

```bash
make hooks   # once per clone: git config core.hooksPath .githooks
make scan    # on demand, working tree and full history
```

The pre-commit hook runs gitleaks from its container image, so nothing has to be
installed locally. If neither gitleaks nor docker is available it fails rather than
passing silently. CI runs the same scan over the full history on every push and PR.

False positives go in `.gitleaks.toml` as a narrow rule — never by disabling the hook.

## Notes
- Debian/Ubuntu only. Both playbooks refuse to run elsewhere rather than failing halfway.
- apt-based tools (docker, gh, podman, jq, wezterm) go through the `apt`
  module and its repositories; the rest are binary downloads gated by a version probe.
- - Daemons install but are not started or enabled — that is left to the machine's owner.
