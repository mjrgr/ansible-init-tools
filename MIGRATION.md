# Migrating a machine from the Ansible setup to mise

For a box that `install_clis.yml` and `dotfiles.yml` provisioned. Nothing here
is destructive until the two cleanup scripts, and both are dry-run by default.
Fresh machine: skip this, follow the README.

## What changed

| | Before (Ansible) | After (mise) |
|---|---|---|
| CLI tools | `playbooks/roles/<tool>`, binaries in `/usr/local/bin`, sha256 in each role's defaults | `mise/config.toml` pins, `mise/mise.lock` URLs + sha256, binaries under `~/.local/share/mise` |
| apt tools (gh, jq, ripgrep, fd, bat, zoxide, age) | distro version, unpinned, `fdfind`/`batcat` shims | mise tools, pinned, upstream names |
| cargo | rustup-init to `/opt/rust`, `cargo`/`rustc` symlinked into `/usr/local/bin` | `rust` core tool, toolchain in `~/.rustup`, `~/.cargo` |
| clauth | `cargo install` from the dotfiles play | `cargo:clauth` mise tool |
| Claude Code | native installer into `~/.local/share/claude`, self-updating | `aqua:anthropics/claude-code`, pinned by the lock, `DISABLE_AUTOUPDATER=1` |
| krew | bootstrapped into `~/.krew`, plugins from the clis play (as the user) | no krew: `stern`, `kubectl-cnpg`, `krelay`, `kubectl-whoami` are mise tools |
| System packages, podman, wezterm, vscode | apt roles | `scripts/bootstrap.sh` (apt and dnf) |
| mise | `mise` role | `scripts/bootstrap.sh`, pinned and checksummed |
| Dotfiles | `dotfiles.yml`, one role per group | `mise run dotfiles`, one task per group under `mise/tasks/dotfiles/` |
| Rollback | `dotfiles_rollback.yml` | `mise run rollback` |
| `K9S_FEATURE_GATE_NODE_SHELL`, `BAT_THEME` | exported in `.zshrc` | `[env]` in `mise/config.toml`, plus `KIND_EXPERIMENTAL_PROVIDER=podman` |
| Version drift, checksums | `test/pin-drift.sh`, `test/bump-pins.sh`, `test/checksums.py` | `mise outdated`, `make bump` (`mise upgrade --bump`), `mise lock` |
| `clis_state=latest` | apt packages to their latest | `scripts/bootstrap.sh --upgrade` (its own packages only); `make upgrade` = that + `make bump` |
| Tests | ansible in a container | bootstrap + mise in a container (Ubuntu 22.04, 26.04, Fedora 43, arm64) |

Not migrated, and why:

| Item | Reason it stays out of mise |
|---|---|
| git, curl, wget, gnupg, unzip, zsh, fontconfig, python3, build-essential, pkg-config, OpenSSL headers | system packages mise and the cargo builds need (a shell, a fetcher, a linker, libs); root-only |
| podman + podman-docker, `/etc/containers/*` | system package with subuid/netavark/systemd integration; config under `/etc` |
| wezterm, vscode | GUI applications with desktop integration (`.desktop`, xdg, terminfo), from their official repositories; root-only |
| mise | the bootstrap, by definition |
| `chsh` | per-user, but it is the login shell: stays a task that asks your password, not a tool |
| `herd-publish.service` | a user unit, not a tool: enabled by the `dotfiles:herdr` task |

Nothing left requires Ansible.

## Steps

Everything the old setup installed keeps working during the migration: the
`/usr/local/bin` binaries are only removed at step 6, and mise's paths come first
on PATH from step 4 on.

### 0. Pull, and know what will move

```bash
cd ~/workspace/.../ansible-init-tools && git pull
ls -la ~/.config/mise 2>/dev/null     # becomes a symlink into the repo; a real dir is backed up
cat ~/.config/mise/config.toml 2>/dev/null   # anything in here must move to mise/config.local.toml
```

If you had a global mise config of your own, copy its `[tools]`/`[env]` into
`mise/config.local.toml` (gitignored, loaded after the versioned one) before
step 4, or they are backed up to `~/.dotfiles-backup/mise.<stamp>/` and stop
applying.

Optional belt and braces:

```bash
tar czf ~/pre-mise-$(date +%F).tgz ~/.claude/settings.json ~/.config/mise ~/.zshrc ~/.zshenv 2>/dev/null
```

### 1. Bootstrap (sudo)

```bash
scripts/bootstrap.sh         # later runs: mise run bootstrap (-- --upgrade)
```

On an already provisioned box this is mostly a no-op: packages are present,
podman is present, the apt sources are rewritten in place, and mise is
reinstalled only if the installed version differs from the pin. It adds the
cargo build prerequisites (C/C++ toolchain, OpenSSL headers, pkg-config) and
`python3` if they were missing.

### 2. Install the tools (no sudo)

```bash
mise trust mise/config.toml
mise run install        # ~1.5 GB of downloads; rust + the clauth build take a few minutes
```

`mise run install` reads `mise/mise.lock` and verifies every download against
it. Tools you already had through another mise config are reused. The `github:`
backend tools ask `api.github.com` for release metadata: on a shared egress
(corporate proxy, CI), set `MISE_GITHUB_TOKEN` to any token first.

### 3. Deploy the dotfiles (no sudo)

```bash
mise run dotfiles
exec zsh
```

What is new for a machine that already had the dotfiles: `~/.config/mise` is
linked to `mise/` in the repo (the tools, env and tasks become global),
`.zshenv` now puts the mise shims on PATH, `.zshrc` activates mise before
anything probes for a tool, `~/.config/btop/themes` links to the themes mise
unpacked, and the `herd-publish` unit is restarted with a PATH that can find
`herdr` and `jq`. Everything else is the same symlink it was.

### 4. Verify

```bash
mise doctor                       # no problem reported; shims dir and activate both listed
mise ls --missing                 # empty
type -a kubectl                   # mise's path first, /usr/local/bin/kubectl second (until step 6)
kubectl version --client && k9s version -s && codex --version && claude --version
kubectl cnpg version && kubectl whoami --version && stern --version
herdr --version && systemctl --user status herd-publish.service
zsh -ic 'echo $KIND_EXPERIMENTAL_PROVIDER $BAT_THEME'   # [env] applied
```

From Windows, for the WezTerm picker: `wsl.exe -d <Distro> -- herdr --version`
must answer. It goes through `.zshenv`, where the shims are.

### 5. Remove Ansible

```bash
scripts/uninstall-ansible.sh          # dry run: lists the package, pip/pipx installs, dirs
scripts/uninstall-ansible.sh --yes
```

Covers the apt/dnf package and its PPA source, pip and pipx installs of
`ansible`, `ansible-core`, `ansible-lint`, `ansible-compat`, `~/.ansible`
(collections, galaxy cache, tmp), `~/.ansible.cfg`, `/etc/ansible`, the lint
caches and `/tmp/ansible-clis.log`, then reports anything still on PATH.

**Only if nothing else on the box uses Ansible.** This repo does not; other
repos might. The script does not know, so it does not guess.

### 6. Clean up what Ansible installed

```bash
scripts/cleanup-legacy.sh             # dry run
scripts/cleanup-legacy.sh --yes
```

Removes the `/usr/local/bin` binaries the roles placed (every tool now in mise,
plus the `cargo`/`rustc`/`fd`/`bat` symlinks), `/usr/local/{share,lib}/nvim`,
`/usr/local/share/btop`, `/opt/rust`, the apt packages now pinned in mise and
the GitHub CLI apt source, the native Claude Code install, and `~/.krew` (the
plugins are mise tools). `/var/lib/docker`, `~/.cargo` and `~/.rustup` stay.

Run it only after step 4 passed: until then the old copies are the fallback.

## Per-system notes

### Debian / Ubuntu

- `sudo-rs` on Ubuntu 25.10+ no longer matters: nothing here uses Ansible's
  become, the bootstrap is a plain `sudo` and the dotfiles ask your password
  through `chsh` only.
- The apt sources the roles wrote (`github-cli.list`, `vscode-msft.list`,
  `wezterm-fury.list`) are rewritten by the bootstrap under the same names;
  `github-cli.list` goes away with `cleanup-legacy.sh`.
- Ubuntu 22.04 is the oldest release the binaries are tested on (glibc 2.35).
  Its git (2.34) rejects `merge.conflictStyle = zdiff3` from the deployed
  `.gitconfig` with a fatal error — a pre-existing limit of the dotfiles, not
  of the migration. The tasks isolate their own clones from it
  (`GIT_CONFIG_GLOBAL=/dev/null`); for your own git on 22.04, install git from
  the `git-core` PPA or override `merge.conflictStyle` in `~/.gitconfig.local`.
- Also on 22.04: the memex herdr plugin has no prebuilt binary for its glibc
  and its source build needs a gcc newer than 11 (AVX512-FP16 intrinsics), so
  `mise run dotfiles` fails on the herdr group unless
  `DOTFILES_HERDR_PLUGINS=false` is set. CI runs 22.04 that way.

### Fedora / RHEL

- The bootstrap uses `dnf`. `chsh` comes from `util-linux-user`, installed if
  missing. `gnupg2` is the package name.
- WezTerm: Fedora goes through `dnf copr enable wezfurlong/wezterm-nightly`
  (upstream's documented route). RHEL-family has no repository: the bootstrap
  prints where to get the rpm and continues.
- podman: Fedora's `/etc/containers/registries.conf` already lists `docker.io`
  in `unqualified-search-registries`, so the Ubuntu drop-in is not written.
  Docker CE removal uses the same package names.
- SELinux: everything mise installs lives under `$HOME` and runs as you; no
  policy change needed. The bootstrap writes nothing under `/opt`.
- Not tested on RHEL/Rocky/Alma itself, only on Fedora 43 in CI.

### WSL

- `systemd=true` under `[boot]` in `/etc/wsl.conf` (then `wsl --shutdown`) for
  the `herd-publish` user unit; without it the task skips the unit and says so.
- The Windows-side WezTerm still reads `%USERPROFILE%\.wezterm.lua` → the
  `mklink` in the README is unchanged. Its `Ctrl+Shift+A` picker runs
  `wsl.exe -- herdr`, which now resolves through the shims `.zshenv` adds.
- `~/.kube` on a drvfs mount: the tasks never re-apply a mode on a directory
  that exists, same as before.
- WSL's `autoProxy` injects `HTTP(S)_PROXY`; mise honours it, and `.zshrc`
  adds the loopback `NO_PROXY` it forgets.
- The Linux `wezterm` and `code` packages are installed as before (the
  bootstrap does not special-case WSL); `--skip wezterm,vscode` if you only
  want the Windows-side ones.

## Behaviour differences worth knowing

- Tools are per-user. `sudo kubectl` finds nothing; `sudo env "PATH=$PATH" kubectl` does.
- `mise install` rewrites `mise/mise.lock` through the `~/.config/mise` link.
  That is the point (the lock is versioned), so expect it in `git status` after
  a `make bump` or `make upgrade`, and commit it.
- Claude Code no longer self-updates; `mise upgrade claude` does, and `mise
  outdated` says when.
- `make bump` installs as well as bumping the pins, where `bump-pins.sh` only
  edited the tree. `make upgrade` also asks for sudo: it moves the bootstrap's
  packages first.
- The `[env]` entries apply in shells where mise is activated and under `mise
  exec`; a bare `zsh -c` sees the shims but not the env.
- Nothing probes `--version` any more: mise decides from its own install
  records, so the `certigo_reported_version` workaround for a binary that
  misreports its version is gone with the probe.

## Rolling the migration back

`mise run rollback` unlinks the dotfiles (including `~/.config/mise`) and
restores the backups. The tools stay under `~/.local/share/mise` and leave PATH
with the config. If `cleanup-legacy.sh` has not run, the old `/usr/local/bin`
binaries are still there. The Ansible playbooks are in git history: `git log
--diff-filter=D --name-only -- playbooks | head` finds the commit that removed
them, and `git checkout <that>^ -- playbooks ansible.cfg inventory` brings them
back.
