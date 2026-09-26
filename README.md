
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
| Privileges | `become: true` (sudo) | `become: false`, except the one-off `chsh` |
| Writes to | `/usr/local/bin`, `/etc/apt` | `$HOME`, `$HOME/.config` |
| Purpose | system-wide tooling | per-user configuration |

## Included CLIs / utilities
- kubectl, helm, kind, kwok, k9s, sofka, argo9s, krew, helmfile
- docker, podman, nerdctl, crictl
- opentofu
- yq, jq
- gh
- sops, age, certigo
- starship, wezterm, vscode
- btop, lazygit, fzf, glow, vhs, gitlogue
- codex (OpenAI Codex CLI), herdr (coding-agent session runtime)
- eza, ripgrep, fd, bat, zoxide, delta
- cargo
- git, make, curl, wget, gnupg, unzip, fontconfig

WezTerm comes from the official apt repository (`apt.fury.io/wez`): the distro
packages lag several releases behind. Same reasoning for VS Code and
`packages.microsoft.com` — with one extra step, since the `code` package installs
its own copy of that repository from its postinst. The role preseeds
`code/add-microsoft-repo=false` so apt is not left with two `Signed-By` lines for
the same URL, which makes it refuse the whole of `sources.list.d`.

Codex CLI is installed from the GitHub release asset rather than `npm i -g
@openai/codex`: the npm and pip packages only wrap the same static binary, and
neither node nor python is otherwise a dependency here. It is a ~250 MB binary —
it embeds its sandbox helpers and its own ripgrep. Unlike Claude Code it does not
self-update, so `codex_version` is pinned like every other binary role.

The role installs a second binary next to it, `codex-code-mode-host` (~69 MB).
It is not optional in practice: `codex features list` reports `code_mode_host` as
stable and enabled, and the feature fails at runtime with *install
`codex-code-mode-host`* when the helper is missing — which is what a bare
`codex` binary leaves you with. Upstream's `install.sh` places it beside the codex
binary, so `/usr/local/bin` is where it goes here. It carries no `--version`, so
it is checked for existence rather than through the version probe: a box
provisioned before this task existed has codex at the pinned version and no helper,
a state the probe alone reports as up to date.

certigo is pinned to v1.18.0, the first release that ships a `linux-arm64`
asset. That binary answers `--version` with `1.17.1`: upstream builds without
ldflags and did not bump the constant in `cli/cli.go`. Left alone, the probe
would see 1.17.1 against a v1.18.0 pin and refetch on every run, so the role
carries a `certigo_reported_version` map keyed by tag. A later bump falls
outside the map and compares the real number again; if that tag misreports
too, `make test-clis` fails on its second pass rather than the machine
silently redownloading forever.

The Rust CLIs are split by how fast they move. `rust_clis` takes ripgrep, fd, bat
and zoxide from apt in one batch, and shims `fdfind`/`batcat` back to `fd`/`bat` —
Debian renames them to avoid a clash with fdclone and bacula. eza and delta get
their own roles and pinned binaries: the apt versions are a year or more behind
and predate options the deployed configs use.

`cargo` is a build toolchain, not a CLI anyone runs directly here: it exists so
`dotfiles_herdr` can build the herdr plugins that ship as source
(herdr-agent-usage, herdr-navigator, clauth). Apt's cargo (1.75 on 22.04/24.04)
is years behind and cannot build clauth, which needs the `edition2024` cargo
feature — stabilized in rustc 1.85 — so the role bootstraps a current
toolchain with `rustup-init` instead, pinned and checksummed like every other
binary role. `rustup-init` only bootstraps: the toolchain it installs is
whatever "stable" resolves to at run time, so the pin guards the installer,
not the compiler version. It installs to `/opt/rust`, not `$HOME/.cargo` —
`install_clis.yml` runs as root, and a toolchain under `/root` would be
invisible to every other user, including the unprivileged `dotfiles.yml` play
that later builds herdr's plugins. Without it, `dotfiles_herdr` skips those
plugins silently — each lists `cargo` under `requires` and a missing
requirement is a skip, not a failure, so a box that never ran `make install`
for this role just has a quieter herdr sidebar and no error to explain why.

## Managed dotfiles

| Group | Deployed to |
|---|---|
| `zsh` | `~/.zshrc`, `~/.zshenv`, oh-my-zsh + 3 external plugins, `~/.config/zsh/wezterm.zsh`, `~/.kube/k8s-clusters.sh` |
| `starship` | `~/.config/starship.toml` |
| `fonts` | JetBrainsMono Nerd Font into `~/.local/share/fonts` |
| `claude` | Claude Code into `~/.local/share/claude`, symlinked at `~/.local/bin/claude` |
| `tmux` | `~/.tmux.conf` |
| `git` | `~/.gitconfig` |
| `wezterm` | `~/.config/wezterm/wezterm.lua`, `~/.config/wezterm/claude-state-hook.sh`, and the hook registration merged into `~/.claude/settings.json` |
| `btop` | `~/.config/btop/btop.conf` |
| `herdr` | `~/.config/herdr/config.toml`, `herd-publish.sh` + its user unit, `claude-statusline.sh`, `quota-status.sh`, `~/.config/herdr-automatic-rename/config.sh`, the generated `~/.claude/skills/herdr/SKILL.md`, and the pinned marketplace plugins |

Each one is a symlink into `dotfiles/` in this repo, so an edit made in `$HOME` shows
up in `git status` with no copy-back step. Two entries are not links: `fonts` installs
a font, and the `wezterm` group merges its Claude Code hooks into an existing
`~/.claude/settings.json` rather than replacing a file that is not ours.

The Nerd Font is not cosmetic: `starship.toml` and `wezterm.lua` use Private Use Area
glyphs, and without the font the prompt and the tab bar render tofu.

Tab-bar icons drop their colour on the active tab. Every literal in there is tuned
against the bar — near-black on Mocha, near-white on Latte — but the active tab paints
itself `ansi[5]`, and measured against that background no literal clears 2.4:1: k9s
lands at 1.03, which is invisible rather than merely dim. On the active tab the icons
fall back to `fg`, which is `on_accent` and readable by construction (7.8 and 4.3).
The shape is what identifies an icon; the colour is a bonus the active tab does not
get. For the same reason the herd marks use Nerd Font glyphs and not `⏸` U+23F8, which
JetBrainsMono does not carry and which the emoji font would render coloured.

### herdr and the tab bar do not see the same thing

herdr is itself a multiplexer, so a WezTerm pane running it reports `herdr` as its
foreground process and carries no user vars from the agents inside: `runs_claude`,
`claude_state` and the rest of the per-pane detectors go dark the moment you work
through it. `claude-state-hook.sh` still fires, but its OSC 1337 lands on a herdr
pty rather than on WezTerm's.

Two things bridge that gap, and neither replaces the hook — the hook is what still
works when herdr is not in the picture.

`ui.toast.delivery = "terminal"` hands herdr's notifications to WezTerm, which raises
a desktop toast. In-app toasts (`"herdr"`, the default this config overrides) are
invisible exactly when they matter: when the terminal is not focused.

The WezTerm tab that hosts herdr carries a `󰳆` sheep and reads its title rather
than its cwd: herdr is a
multiplexer, so its cwd is wherever it was launched — `~` in practice — while
`ui.window_title` tracks the workspace and tab you are actually in. The template
stays under `TITLE_MAX`, and leaves `{terminal_title}` out: that token substitutes
the agent title *stripped* of its state glyph, so it costs a third of the tab width
and carries no state.

The `herdr: ` prefix is what the match keys on — the same load-bearing colon
`sofka` uses, and for the same reason. A process check is not an option on the
Windows side: a WSL pane exposes the Windows process tree, never the distro's
`/proc`, so `foreground_process_name` never says `herdr` there.

The right status bar carries the whole herd — `󰳆 2󰉁 1󰏤` for two agents working and
one blocked, and the glyph on its own when every agent is idle. Idle carries no
count on purpose, but the indicator still has to be on screen: one that disappears
when nothing is happening cannot be told apart from one that disappeared because it
broke. The publisher stamps each line with the time it wrote it, and a line older
than `HERD_STALE_AFTER` reads as absent — so the glyph really does mean the
publisher is alive. That window is wide (120 s) because the stamp is written by WSL
and read by Windows, and the two clocks drift apart across a suspend. It reads a file, never a process: `update-right-status` runs on the GUI
thread once a second, and asking herdr from there would put `wsl.exe` on that thread,
~100 ms of frozen UI per tick. `herd-publish.sh` pays the crossing instead, from a
systemd user unit, writing into `LOCALAPPDATA` so the GUI reads an NTFS path. It polls
rather than blocks: `herdr agent wait` needs a target and cannot watch the herd as a
whole, and a snapshot over the unix socket costs ~8 ms.

The unit is what makes this survive: the publisher has to outlive the shell that
started it and come back when it dies, which a backgrounded loop in `.zshrc` gives
neither. A host with no user systemd — a container, notably — skips the whole block.

`herdr --skill` is rendered into `~/.claude/skills/herdr/SKILL.md` at deploy time
rather than versioned here: it documents the CLI of the herdr that printed it, so a
copy committed to this repo would drift into teaching Claude commands that no longer
exist. `update.version_check` and `update.manifest_check` are off for the same reason
the binary is pinned — the version is decided by `playbooks/roles/herdr`, not by a
background call to herdr.dev.

Marketplace plugins are pinned the same way, to a commit rather than a tag, in
`dotfiles_herdr_plugins`. A plugin is code that runs as you with your whole
environment — tokens, kubeconfigs — so `--ref` has to name bytes someone read, and a
tag can be moved after the fact. `herdr plugin install` re-clones and replaces on
every call, so the role reads `herdr plugin list --json` first and installs only
what is absent or sits on another commit. Each entry says which tools its build
needs; a host without them (the container, a box with no Rust toolchain) skips that
plugin and reports it rather than failing. `clauth` itself comes from crates.io
because upstream publishes no linux-arm64 asset and a binary role here has to
checksum both targets. There is no rollback for plugins beyond `herdr plugin
uninstall <id>`.

`herdr-automatic-rename` reads `~/.config/herdr-automatic-rename/config.sh`, a path
of its own rather than `herdr plugin config-dir`. The committed one turns off the
`[N]` jump-key prefix on tabs and workspaces (`AUTO_INDEX=0`): the sidebar rows
already name each agent, and the prefix was spending sidebar width on a number the
`prefix+N` keys work without. Prefixes already on screen go with the plugin's
`clear` action, not the toggle.

`herdr-agent-usage` is the one plugin that reaches outside its own directory, and
its `configure --apply` action is where the agreements below come from. It rewrites
three things: the `[ui.sidebar.agents]` rows in `config.toml` (a symlink into this
repo, so the write lands in `git status`), Claude Code's `statusLine` in
`~/.claude/settings.json`, and the `[[keys.command]]` entries it wants. Run it once
after a bump, then put the two hand edits back:

- **statusLine.** The plugin reads the 5h/7d quota through Claude Code's statusLine
  hook and has no pass-through, so its `configure` replaces ccstatusline with its own
  renderer. `claude-statusline.sh` feeds the same session JSON to both and draws only
  the command given as arguments — ccstatusline by default, or a project's own status
  line when its `.claude/settings.json` overrides the global one, which `mjgbrain-v2`
  does. Point `statusLine.command` at the script again after every `configure`. It
  globs the plugin's checkout directory rather than naming it: the directory carries
  a hash that follows the pinned ref, and a stale path would drop the quota silently.
- **Sidebar rows.** The generated rows put the workspace header on the first agent's
  first row, and herdr indents every row of an agent but its first, so that agent's
  identity line sat two columns right of the others. The committed rows give every
  agent a first row — the header, or the plugin's zero-width nest gap — and the
  identity row is herdr's `state_icon` and `tab`, then provider/model in Claude
  orange (`$quota_model` alone is not published in the `gauges` layout).
  The plugin's vendor mark was tried in place of `state_icon` and dropped: it
  carries padding meant for the plugin's own layout, and herdr separates it from
  the tab with ` · `, so the rows no longer lined up.
  The last row is the plugin's context meter, `cx ▰▱▱▱▱▱ 16%`, which it only
  publishes in its `gauges` layout, green, then yellow past 50 % used and red past
  80 %. The layout and the used-not-remaining style are two files in the plugin's
  state directory; the role writes them directly (`dotfiles_herdr_agent_usage_prefs`)
  because `configure` would rewrite the rows and the statusLine along with them.
  The second row is herdr's `terminal_title_stripped`, the session title Claude Code
  sets after a few turns (`Claude Code` before that, nothing for Codex), rather than
  the plugin's `$quota_topic`, which scrapes the last visible `❯` line and shows a
  reply once the prompt has scrolled off. The third row is model and context
  pressure, the two things that change how a session behaves. The quota tokens are
  gone from the rows on purpose: the quota is per account, and one copy per agent
  pane was the same bars repeated.

The quota lives in the tab bar instead, once: `quota-status.sh` runs from
`ui.tab_bar_right` every 30 s, reads the plugin's state files and prints one line per
provider — hourglass and calendar-week glyphs for the 5h and 7d windows, a
circle-slice pie for what is left, the number only below 100 %, `?` when the last
observation is older than three hours. A provider at 100/100 still shows, without
numbers. The statusLine wrapper is what keeps those files fresh, so a Claude session
started before the wrapper was installed, or one whose project settings bypass it,
reports nothing until it is restarted with `claude --continue`.

`Ctrl+Shift+A` opens a fuzzy picker over `herdr agent list` and focuses the one you
choose, across every workspace and SSH machine in the session. The state marks come
from herdr's own `agent_status`, which is finer than the hook's: `⚡` working,
`⏸` blocked on a permission prompt, `✓` done, `·` idle.

It calls `herdr` through `wsl.exe` on the Windows side, in a non-login shell whose
PATH covers `/usr/local/bin` but not `~/.local/bin`. So the picker only works against
the binary `install_clis.yml` installs — a copy left in `~/.local/bin` by herdr's own
installer is invisible to it, and `herdr update` would keep that copy, not this one.

The zsh and WezTerm configs work together: `~/.config/zsh/wezterm.zsh` emits OSC 133
semantic zones and publishes the current kubectl context as a user var, which
`wezterm.lua` renders in the tab title and right status bar. In the tab title it turns
matrix green while `k9s` or `sofka` is running, so the color means "pointed at this
cluster right now" rather than just "what kubectl would target".

The color scheme follows the desktop light/dark preference *live*, not only at
startup: `window-config-reloaded` re-derives it and pushes titlebar and tab-bar
colors along with it, which a bare `color_scheme` override would leave behind.

A background tab marks itself with an amber ● once it has produced output you have
not looked at, and the bell — silent since `audible_bell` was disabled — now flashes
the cursor.

A tab also shows a 󰚩 in Claude's own coral (`#DE7356`) while a Claude Code
session runs in any of its panes.
Detection is two-layered: reading the pane's foreground process needs no shell
cooperation, but only recognises the native binary at
`~/.local/share/claude/versions/<semver>` (an npm install runs under `node` and
stays invisible), and it cannot see into a pane at all when the WezTerm GUI and
the pane's shell are on opposite sides of a WSL boundary — see below. The
`claude` zsh wrapper (`~/.zshrc`) backs it up by setting a `claude_active` user
var over OSC 1337, which rides the terminal byte stream instead of the process
tree and works in both cases.

The icon's colour is the session's state, not just its presence: coral while
Claude is working, green once it is waiting on you, and the plain tab foreground
otherwise. That comes from `claude-state-hook.sh`, which Claude Code runs on
`UserPromptSubmit`, `Stop`, `Notification`, `SessionStart` and `SessionEnd`, and
which publishes a `claude_state` user var the same OSC 1337 way. The waiting
green survives until you focus the tab, like the bell marker — on the tab you are
already looking at, the answer is on screen.

Two things have to be true for the colour to move, and the script being deployed
is only one of them. Claude Code runs hooks it finds registered in
`~/.claude/settings.json`, so the `wezterm` group merges those five events into
that file — merged rather than symlinked, because it is the user's own file and
holds tokens and machine-local preferences beside the hooks. A deploy that lands
the script without the registration leaves the icon permanently grey. The hooks
also need the pane's tty, which hooks do not reliably inherit; the `claude` zsh
wrapper passes it as `CLAUDE_STATE_TTY`. Headless runs (`-p`, the SDK) have no
tty to write to and stay silent by design.

`SubagentStop` is deliberately not registered: it fires when a subagent finishes
while the main agent keeps working, which would turn the tab green with nothing
actually waiting on you.

A monochrome 󰧑 marks a tab running the OpenAI Codex CLI — white on Mocha,
Latte's ink (`#4c4f69`) once the desktop flips to light, since white on a `#eff1f5`
titlebar is not there. That is the one icon colour that cannot be a fixed literal,
so the scheme in force is kept in a local rather than read back from the handler's
`config` argument, which is the load-time one and does not carry the overrides
`window-config-reloaded` applies. The glyph, not the colour, is what separates it
from the claude icon.

Unlike claude the binary is a plain `/usr/local/bin/codex`, so the process check
recognises it by leaf name. There is no title fallback here the way `k9s` has one:
codex overwrites the pane title with the cwd basename once its TUI is up, so
matching the title lit the tab for the second or two before that and then dropped
it — and it would have fired in any directory named `codex`. A `codex` zsh wrapper
sets a `codex_active` user var instead, same mechanism as `claude`.

A blue 󱃾 marks a tab running `k9s`. The process check is blind under WSL for the
same reason, so the fallback here is the pane title: oh-my-zsh's `termsupport`
sets it to the running command, and a title crosses the WSL boundary because it
travels in the byte stream. No shell wrapper needed. The kube-context suffix
drops its own glyph while that icon shows, so the tab never carries the same
symbol twice.

A grey-blue 󰄛 marks a tab running `sofka`. It is a cat rather than a second kube
glyph on purpose: sofka and k9s do the same job, and two icons that differ only
by colour are indistinguishable at tab-bar size. Detection is the same two
tracks, with a sturdier title than k9s's — sofka writes `sofka: <context>/<namespace>`
on every change and clears the title on exit (`terminal_title`, on by default),
so no shell wrapper is needed and the tab never stays lit after the TUI is gone.
The match keeps the colon: a bare `^sofka` also fires on a shell sitting in a
directory named `sofka`, which is where this config gets edited. The kube-context
suffix keeps its 󱃾 here, unlike under k9s — the cat does not carry that meaning —
and turns matrix green, which reads "you are pointed at this cluster right now".

An orange ● marks a tab where a command is running. WezTerm's own
`has_unseen_output` looks like the obvious source and is not: it means "bytes
arrived since you last focused this pane", and an invisible OSC 133 sequence or
a background redraw sets it just as well as real work does, so it stays lit on
idle tabs until you visit them. A `busy` user var set in `preexec` and cleared
in `precmd` tracks the shell instead of the byte stream. The dot is hidden when
an agent, k9s or sofka icon already shows — those say the same thing — and on the
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

The distro name is baked into that UNC path, so renaming or removing the distro
breaks the link and WezTerm silently falls back to its built-in defaults — no
error, just a terminal that lost its config. Check the target and re-create it:

```powershell
(Get-Item C:\Users\<you>\.wezterm.lua).Target     # dangling if the distro was renamed
Remove-Item C:\Users\<you>\.wezterm.lua -Force
New-Item -ItemType SymbolicLink -Path C:\Users\<you>\.wezterm.lua `
  -Target '\\wsl.localhost\<Distro>\home\<you>\workspace\...\ansible-init-tools\dotfiles\wezterm\wezterm.lua'
```

From WSL, `ls -la /mnt/c/Users/<you>/.wezterm.lua` reports `Input/output error`
on the symlink when the target distro no longer exists.

## Usage

`make help` lists everything. The common paths:

```bash
make install     # CLI tools (sudo) — installs only what is missing
make upgrade     # re-run every installer and upgrade in place
make dotfiles    # deploy the dotfiles (no sudo)
make rollback    # remove the symlinks, restore the backups
make test        # deploy in a container, assert idempotence
make lint        # yamllint + ansible-lint + syntax check + checksum audit
make checksums   # refetch every pinned asset and record its sha256
make scan        # scan the tree and history for secrets
make hooks       # enable the pre-commit secret scan
```

The underlying commands, when you need finer control:

```bash
ansible-playbook playbooks/install_clis.yml -c local --ask-become-pass
ansible-playbook playbooks/dotfiles.yml -c local --ask-become-pass
```

### Ubuntu 26.04: sudo-rs breaks `--ask-become-pass`

Ubuntu 25.10 and later ship `sudo-rs` as `/usr/bin/sudo`. Ansible's `sudo` become
plugin hands the password to the child on stdin, which sudo-rs does not take the way
`sudo -S` does — it re-prints a prompt of its own and keeps waiting, so every play
dies on the first task:

```
[ERROR]: Task failed: Timed out waiting for become success or become password prompt.
>>> Standard Error
[sudo: [sudo via ansible, key=...] password:] Password:
```

`sudo --version` tells them apart — `sudo-rs 0.2.x` versus `Sudo version 1.9.x`.
Having the `sudo` package installed proves nothing: sudo-rs owns the path either way.
Swap it back, and keep a root shell open in a second terminal until the new binary
answers, since the removal takes away the `sudo` in use:

```bash
sudo apt-get install --reinstall -y sudo
sudo apt-get remove -y sudo-rs
sudo --version | head -1
```

A `NOPASSWD` drop-in in `/etc/sudoers.d` is the other way out — sudo-rs reads it — but
it trades one interactive password for permanent passwordless root on the account.

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
| `dotfiles_set_default_shell` | `true` | `chsh` to zsh — needs `--ask-become-pass`, on that run only |

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

### The pin says which version, the checksum says which bytes

A version pin alone buys reproducibility, not integrity: a git tag is mutable, a
release asset can be replaced under it, and a download that goes through a proxy or a
compromised mirror arrives with nobody the wiser. So every binary download also
carries the sha256 it must hash to, next to the version that names it:

```yaml
kind_version: "v0.33.0"
kind_sha256:
  amd64: "aee6151561422756b764a4ae28e7f44cda5af5a9eead3cc9985112b1de8d8e0d"
  arm64: "20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2"
```

`get_url` verifies before the file is installed, so a mismatch fails the run instead
of landing in `/usr/local/bin`. Bumping a version means refreshing the digests:

```bash
make checksums            # refetch every pinned asset, write its digest back
make checksums-audit      # offline: assert no pinned version is missing one
```

Digests are never edited by hand — a hand-copied digest is one nobody rechecked.
`make lint` runs the offline audit, CI runs it on every PR, and a weekly job refetches
every asset and reports any that no longer hashes to what the repo says: an artefact
that was supposed to be immutable and was not is worth knowing about.

A version pinned to `latest` cannot be checksummed ahead of time, and its digest is
blanked to say so. That is the cost of not pinning, made visible rather than implied.

The digest proves the bytes are the ones upstream published; it says nothing about
whether they run on this machine. So each role also executes what it just installed.
A musl build on a host that needs glibc, or a wrong architecture slug in a map, both
download perfectly and then fail on first use — which is a worse place to find out.

The apt-installed tools are outside this: their packages are verified against the
repository signing key in `/etc/apt/keyrings`, which is the same guarantee by
another route.

### Architectures

`x86_64` and `aarch64`. Every role maps those onto whatever its upstream calls them —
there is no agreement whatsoever (`linux-amd64`, `x86_64-unknown-linux-gnu`,
`Linux_x86_64`, and starship publishes a gnu build for x86_64 and only a musl one for
aarch64) — so the mapping lives in each role's `<role>_arch` default. A host that is
neither fails with a named error rather than a 404 mid-download. CI installs the whole
set on both.

Not pinned, and why:

| Tool | Reason |
|---|---|
| docker, gh, podman, jq, wezterm, vscode, rust_clis | installed from apt repositories, which track whatever apt has at install time; the distro decides the version, and apt's signature check is what guards the download |
| claude | self-updating, and installed per user by the dotfiles play; pick a train with `dotfiles_claude_channel` |

**Dependabot does not watch these pins** — no ecosystem understands versions living in
Ansible defaults. It covers the GitHub Actions only, which are pinned by commit SHA
with the version in a trailing comment: a tag is mutable and an action runs with the
workflow's permissions. What
guards the pins is `make test-pins`, which installs every pinned version in a
container and fails on a yanked tag or a changed asset URL. It runs in CI.

`make test-pins` answers "does this pin still install", not "is this pin current" —
a tool can sit three minors behind and stay green forever. `make drift` answers the
second question: it reads the latest release of each tool and prints what has moved
on. CI runs it every Monday and keeps a single `pin-drift` issue in sync with the
result — opened when something lags, edited on later runs, closed when everything
matches again. The upstream repo is read out of each role's own download URL, so a
new role is covered without registering it anywhere; the three tools that do not
download from GitHub (kubectl, helm, starship) are named in the script, and a role
with neither is reported as unknown rather than quietly skipped.

## Bootstrap on a new machine

```bash
git clone <this-repo> && cd ansible-init-tools

# 1. Tools (sudo)
ansible-playbook playbooks/install_clis.yml -c local --ask-become-pass

# 2. Dotfiles + set zsh as the login shell
ansible-playbook playbooks/dotfiles.yml -c local --ask-become-pass

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
./test/run.sh clis [role]     # install_clis.yml twice, asserts nothing refetches
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

CI also runs the container targets on an `arm64` runner, on the current LTS only: the
second LTS axis exists to cover the ansible-core version, not the CPU, so crossing the
two in full would buy nothing for three times the minutes.

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

What `clis` asserts:

- `install_clis.yml` completes on a machine with none of the tools present
- a second pass refetches nothing — again in the **same** container

`changed=0` is deliberately not the assertion there. docker, gh, vscode and wezterm
delete their apt source before `apt_repository` recreates it, so the play reports
`changed` on every run by design. What must hold is that no tool is downloaded twice,
which is what each role's probe decides and prints, and a probe that misreads its own
tool's `--version` output is exactly the bug this catches: `pins` cannot, because it
only ever runs each role once.

Caveat: daemons (docker, podman) install but do not start in a container. The
`chsh` does run — the test user holds a `NOPASSWD` sudoers entry — and it is part
of what the second run proves, since a task that re-applied it would show up as
`changed=1`.

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

The login shell is **not** reverted: `chsh` overwrote the previous value rather than
saving it, so `chsh -s /bin/bash` is the manual step if you want it back.

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
