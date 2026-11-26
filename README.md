# 📥 init tools 🧰

A [mise](https://mise.jdx.dev/) setup for installing a collection of CLI tools
**and deploying personal dotfiles** on **Debian/Ubuntu, Fedora/RHEL and WSL**.

mise owns everything it can: the tools, their pins, their checksums, the
environment variables that go with them and the deployment tasks. One shell
script does what needs root — base packages, podman, WezTerm, VS Code, and the
mise binary itself. Ansible used to orchestrate all of this; it is gone, and
[MIGRATION.md](MIGRATION.md) is the path from a machine it provisioned.

### Features
- ✅ Self-contained: one config file, one lockfile, a handful of bash tasks
- ✅ Idempotent — a re-run installs nothing it already installed, and reports no change
- ✅ Every tool pins to a concrete version, and `mise.lock` carries its sha256 per platform
- ✅ Dotfiles deployed as symlinks into the repo — edit in `$HOME`, `git status` sees it
- ✅ Nothing site-specific is versioned: secrets, proxies and host names stay in local override files
- ✅ Secret scanning in CI and in a pre-commit hook
- ✅ Tested against throwaway containers (Ubuntu 22.04, 26.04, Fedora 43, arm64), not just against the machine that wrote it

## One declaration, one command

Everything the machine needs is declared in `mise/config.toml` and applied by
`mise bootstrap`, in a fixed order: system packages and their repositories
(`[bootstrap.packages]`, `[bootstrap.apt.sources]`, `[bootstrap.dnf.repos]`),
system files, git clones (oh-my-zsh and its plugins), the dotfiles symlinks
(`[dotfiles]`), the login shell, every pinned tool (`[tools]`), then the
`bootstrap` task for what cannot be declared (the Nerd Font, the Claude Code
hooks, herdr's plugins, the publisher unit).

| | `scripts/bootstrap.sh` | `mise bootstrap` |
|---|---|---|
| Privileges | sudo | sudo for the packages and system files, none for the rest |
| Writes to | `/usr/local/bin/mise` | `/etc/apt`, `/etc/yum.repos.d`, `/etc/containers`, `$HOME`, `~/.local/share/mise` |
| Purpose | the pinned mise binary | everything else |

```bash
sudo apt install -y git make       # dnf on Fedora; the only thing the repo does not install itself
git clone <this-repo> && cd ansible-init-tools
make setup                         # mise binary (sudo), trust, link ~/.config/mise, mise bootstrap
exec zsh
```

`make setup` is the one path that starts without mise. From then on `mise
bootstrap` (or `mise run setup`) is the whole thing, `mise bootstrap --dry-run`
and `mise bootstrap status` say what would move, `--only`/`--skip` pick a part
(`packages`, `repos`, `dotfiles`, `user`, `tools`, `task`...), and `make <target>`
is only a shorter spelling. The bootstrap script asks for sudo itself and
carries your proxy variables through it; a hand-typed `sudo scripts/bootstrap.sh`
would drop them before the first `curl`.

## Included CLIs / utilities

Pinned in `mise/config.toml`, installed under `~/.local/share/mise`:

- kubectl, helm, kind, kwok/kwokctl, k9s, popeye, sofka, argo9s, helmfile
- kubectl plugins: cnpg, relay (krelay), whoami; stern
- argocd, kubectx/kubens, kubie, cilium, hubble, kyverno, vcluster, cmctl, k0sctl, telepresence, cloud-provider-kind, helm-schema
- nerdctl, crictl
- opentofu
- trivy, gitleaks, cosign, oras, dive, ko
- shellcheck, yamllint (what `make lint` runs)
- yq, jq, gh, glab
- sops, age, certigo
- starship, fzf, btop, lazygit, glow, gum, vhs, gitlogue
- eza, ripgrep, fd, bat, zoxide, delta
- neovim (LazyVim needs >= 0.11, newer than the distro package)
- codex (OpenAI Codex CLI), claude (Claude Code), herdr (coding-agent session runtime), clauth
- rust (the toolchain the herdr plugins are built with)
- python, uv (with `uvx`, which MCP servers such as garmin and google-workspace run through), node, bun (runtimes; python also lets mise lock the pypi dependency graph)
- openstackclient (python-openstackclient + python-octaviaclient, from PyPI through uv)
- ccstatusline, cloudcli (browser MCP), task-master-ai, open-meteo-mcp-server (npm packages, formerly `npm i -g` under nvm)

Installed by `scripts/bootstrap.sh`, because they are system packages, GUI
applications or need root:

- git, curl, wget, gnupg, unzip, zsh, fontconfig, python3, make, and the cargo build prerequisites (build-essential, pkg-config, OpenSSL headers)
- podman (+ podman-docker for the `docker` CLI)
- wezterm, vscode (their official repositories: the distro packages lag)
- mise itself

Codex CLI is installed from the GitHub release (`aqua:openai/codex`, tagged
`rust-v<x.y.z>`) rather than `npm i -g @openai/codex`: the npm and pip packages
only wrap the same static binaries. The package holds `codex` (~300 MB: it
embeds its sandbox helpers and its own ripgrep), `codex-code-mode-host` (the
helper `codex features list` reports as stable and enabled, and which the
feature needs at runtime) and `codex-exec-server`. None self-updates, so the
package is pinned like every other tool.

Claude Code is a mise tool too (`aqua:anthropics/claude-code`, the native
binary). It is the one entry pinned to `latest`: the lockfile fixes the version
that `latest` resolved to, `mise upgrade claude` moves it, and
`DISABLE_AUTOUPDATER=1` in `[env]` keeps its self-updater from fighting the pin.

`rust` is a build toolchain, not a CLI anyone runs directly here: it exists so
the `bootstrap` task can build the herdr plugins that ship as source
(herdr-agent-usage, herdr-navigator) and so mise can build `clauth` from
crates.io. The distro's cargo (1.75 on Ubuntu 22.04/24.04) is years behind and
cannot build clauth, which needs the `edition2024` cargo feature — stabilized in
rustc 1.85. mise installs the toolchain through rustup under `~/.rustup` and
`~/.cargo`, which `.zshenv` already sources. A C/C++ toolchain, pkg-config and
the OpenSSL headers are in the bootstrap for the same reason: cargo needs them, and a box without them fails `mise install` on clauth rather than quietly
skipping the plugins.

The apt-era CLIs — gh, jq, ripgrep, fd, bat, zoxide, age — are pinned now like
the rest, instead of tracking whatever the distro ships. There is no
`fdfind`/`batcat` renaming either: mise installs the upstream binaries under
their upstream names.

## Managed dotfiles

Symlinks into `dotfiles/` in this repo, declared as `[dotfiles]` entries in
`mise/config.toml` and applied by `mise bootstrap` (or `mise dot apply`); what a
symlink cannot express is done by the `bootstrap` task right after.

| | Deployed to |
|---|---|
| zsh | `~/.zshrc`, `~/.zshenv`, `~/.config/zsh/wezterm.zsh`, `~/.kube/k8s-clusters.sh`, `~/.config/krelay/patch-hardened.json`; oh-my-zsh + 4 plugins cloned by `[bootstrap.repos]` |
| starship | `~/.config/starship.toml` |
| fonts (task) | JetBrainsMono Nerd Font into `~/.local/share/fonts` |
| tmux | `~/.tmux.conf` |
| git | `~/.gitconfig` |
| wezterm | `~/.config/wezterm/wezterm.lua`, `~/.config/wezterm/claude-state-hook.sh`; the hook registration merged into `~/.claude/settings.json` (task) |
| btop | `~/.config/btop/btop.conf`; `~/.config/btop/themes` → the themes shipped in the btop release mise unpacks (task) |
| nvim | `~/.config/nvim` (LazyVim starter, whole directory; `lazy-lock.json` lands in the repo) |
| mise | `~/.config/mise` → `mise/` in this repo: the tool pins, `mise.lock`, `[env]` and the tasks become global |
| herdr | `~/.config/herdr/config.toml`, `herd-publish.sh` + its user unit, `claude-statusline.sh`, `quota-status.sh`, `~/.config/herdr-automatic-rename/config.sh`; the generated `~/.claude/skills/herdr/SKILL.md` and the pinned marketplace plugins (task) |

Each one is a symlink into this repo, so an edit made in `$HOME` shows up in
`git status` with no copy-back step — including `mise.lock`, which `mise install`
rewrites through the `~/.config/mise` link. Two entries are not links: `fonts`
installs a font, and the `wezterm` group merges its Claude Code hooks into an
existing `~/.claude/settings.json` rather than replacing a file that is not ours.

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
the binary is pinned — the version is decided by `mise/config.toml`, not by a
background call to herdr.dev.

Marketplace plugins are pinned the same way, to a commit rather than a tag, in
the `bootstrap` task (`mise/tasks/bootstrap`). A plugin is code that runs as you with your whole
environment — tokens, kubeconfigs — so `--ref` has to name bytes someone read, and a
tag can be moved after the fact. `herdr plugin install` re-clones and replaces on
every call, so the task reads `herdr plugin list --json` first and installs only
what is absent or sits on another commit. Each entry says which tools its build
needs; a host without them (the container, a box with no Rust toolchain) skips that
plugin and reports it rather than failing. `clauth` itself is a mise tool built
from crates.io (`cargo:clauth`) because upstream publishes no linux-arm64 asset. There is no rollback for plugins beyond `herdr plugin
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
  state directory; the `bootstrap` task writes them directly
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

It calls `herdr` through `wsl.exe` on the Windows side, in a non-login shell that
reads `.zshenv` but never `.zshrc`. `.zshenv` is where the mise shims go on PATH,
and that is what makes the picker find the pinned herdr; a copy left in
`~/.local/bin` by herdr's own installer is not on that PATH, and `herdr update`
would move that copy, not the pin.

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

Unlike claude the binary mise installs is a plain `codex`, so the process check
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
WSL's `$HOME` — nothing in this repo reaches there. Point it at the
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
make setup       # fresh box: the mise binary (sudo), then `mise bootstrap` for everything else
make bootstrap   # apply the declared setup; ARGS="--dry-run" | "--only packages" | "--skip tools"
make install     # every pinned tool from mise.lock
make upgrade     # the declared packages to their latest (sudo), every pin to upstream's latest, then check
make bump        # the pins only: upstream's latest, refresh the lock, install (no sudo)
make bump-mise   # the mise pin itself (version + sha256) in scripts/bootstrap.sh, then scripts/bootstrap.sh
make check       # this host: every tool answers, lock audited, mise doctor clean, herd-publish unit up
make dotfiles    # the dotfiles symlinks, then the bootstrap task (fonts, hooks, herdr, chsh, unit)
make rollback    # unlink every dotfiles entry, un-register the Claude hooks, stop the unit
make test        # `mise bootstrap` twice in a container, assert idempotence
make lint        # shellcheck + yamllint + config parse + lock audit
make lock        # refresh mise.lock after editing a pin
make drift       # which pins upstream has moved past
make scan        # scan the tree and history for secrets
make hooks       # enable the pre-commit secret scan
```

The underlying commands, when you need finer control:

```bash
mise bootstrap --dry-run                 # what a run would change, nothing applied
mise bootstrap status                    # every part, converged or not
mise bootstrap packages upgrade          # the declared packages to their latest, nothing else
mise dot apply / mise dot status         # the [dotfiles] entries alone
mise install kubectl helm                # two tools
mise run bootstrap                       # the task alone: fonts, Claude hooks, herdr, chsh, unit
mise tasks                               # every task, with its description
```

Useful knobs:

| Variable | Default | Purpose |
|---|---|---|
| `DOTFILES_SET_DEFAULT_SHELL` | `true` | `false` skips the `chsh` to zsh |
| `DOTFILES_HERDR_PLUGINS` | `true` | `false` skips the herdr plugin installs (memex cannot be built on Ubuntu 22.04) |
| `MISE_GITHUB_TOKEN` | *(unset)* | a GitHub token for the `github:` backend tools; the anonymous API quota is 60 calls/hour per IP |
| `BASE_IMAGE` | `ubuntu:26.04` | the distro the container tests run against (`ubuntu:22.04`, `fedora:43`) |

The tools live under your user, not in `/usr/local/bin`: `sudo kubectl` does not
find them. `sudo env "PATH=$PATH" kubectl` does, when root really has to run one.

## Containers: podman, not docker

There is no Docker Engine. `podman-docker` provides `docker` as a shim over podman:
daemonless, rootless, and no `docker0` bridge — whose default 172.17.0.0/16 route
cut SSH on a VM whose client sat in that range.

On a machine provisioned before the switch, the bootstrap removes the Docker
packages, repository and leftover `docker0`. `/var/lib/docker` is kept; delete it
by hand once nothing in it is needed.

- `docker compose` needs a provider: `podman compose` delegates to `docker-compose`
  or `podman-compose`, neither installed here.
- kind: `KIND_EXPERIMENTAL_PROVIDER=podman`, set in `[env]`.

## Reproducibility

Every tool is pinned to a concrete version in `mise/config.toml`, so two machines
provisioned months apart get the same binary. Override per run, or edit the pin:

```bash
mise install kubectl@1.30.0          # once, outside the config
mise use -g kubectl@1.30.0           # edits mise/config.toml (global = this repo)
```

A re-run is idempotent: `mise install` skips every tool already at its pin.
Moving a pin is detected and reinstalls. `make bump` (`mise upgrade --bump`)
is the explicit opt-in to move every pin past what is written — it rewrites the
config and the lock, so the result is a diff to review, not a surprise. `make
upgrade` does the same after `mise bootstrap packages upgrade`, which moves the
declared system packages (and only those) to their latest, and ends
with `make check`: every tool answers, the lock is audited, `mise doctor` is
clean, the herd-publish unit is up. `make check` on its own is the thing to run
when a shell looks wrong after a `git pull`.

### The pin says which version, the lock says which bytes

A version pin alone buys reproducibility, not integrity: a git tag is mutable, a
release asset can be replaced under it, and a download that goes through a proxy
or a compromised mirror arrives with nobody the wiser. `mise.lock` is where the
bytes are named: for every tool and both Linux platforms, the exact URL and the
sha256 it must hash to.

```toml
[[tools.kind]]
version = "0.33.0"
backend = "aqua:kubernetes-sigs/kind"

[tools.kind."platforms.linux-arm64"]
checksum = "sha256:20022bee6cfcd5086cb7234d218e3454e6090022f2a8f55d1fa7fcf42c3867a2"
url = "https://github.com/kubernetes-sigs/kind/releases/download/v0.33.0/kind-linux-arm64"
```

mise verifies before the file is installed, so a mismatch fails the run instead
of landing on disk. Bumping a version means refreshing the lock:

```bash
make lock          # mise lock: resolve every URL and digest again
make lock-audit    # offline: assert every tool is locked for both platforms with a digest
```

Digests are never edited by hand — a hand-copied digest is one nobody rechecked.
`make lint` runs the offline audit, CI runs it on every PR, and a weekly job
re-resolves every asset and fails when the lock no longer matches: an artefact
that was supposed to be immutable and was not is worth knowing about.

Two entries carry no digest: `rust` (rustup verifies the toolchain it downloads)
and `clauth` (cargo verifies the crate against the registry index). The audit
exempts those two backends by name, not the tools.

Beyond the checksum, mise verifies what the upstream publishes: cosign
signatures and SLSA provenance through the aqua registry, GitHub artifact
attestations for the `github:` backend. aqua is preferred for that reason, and
because it downloads straight from the release URL. The `github:` backend is
used only where the registry has no entry (argo9s, gitlogue, certigo,
kubectl-cnpg, krelay) or where one release holds several tools (kwok); it
reads release metadata from `api.github.com`, which is why `MISE_GITHUB_TOKEN`
exists.

### Architectures

`x86_64` and `aarch64`. mise maps those onto whatever each upstream calls them,
and `lockfile_platforms` restricts the lock to the two Linux targets — the
`matching_regex` entries name no macOS or Windows asset, and locking them would
fail. A host that is neither fails with a named error. CI installs the whole set
on both.

**Dependabot does not watch these pins** — no ecosystem understands versions
living in `mise/config.toml`. It covers the GitHub Actions only, which are pinned
by commit SHA with the version in a trailing comment. What guards the pins is
the `clis` CI job, which installs every locked version in a container and fails
on a yanked tag or a changed asset URL.

That answers "does this pin still install", not "is this pin current". `make
drift` (`mise outdated`) answers the second question. Every Monday the
`pin-bump` job runs `make bump` on a runner and keeps a single PR (`bump/pins`)
carrying the resulting diff, with CI dispatched on the branch to validate it on
the four targets; merge it when green, close it or let it close itself when
nothing lags any more. The job needs the repository setting "Allow GitHub
Actions to create and approve pull requests" (Settings → Actions → General).

## Bootstrap on a new machine

```bash
sudo apt install -y git make      # dnf on Fedora
git clone <this-repo> && cd ansible-init-tools

# 1-2 in one go: make setup. Step by step:
# 1. The pinned mise binary (sudo)
scripts/bootstrap.sh

# 2. Everything else: packages (sudo), repos, dotfiles, login shell, tools, the bootstrap task
mise trust mise/config.toml
ln -sfn "$PWD/mise" ~/.config/mise      # mise bootstrap would link it too, but the lock paths depend on it being global
mise bootstrap --yes                     # --dry-run first if you want to read it
exec zsh

# 3. Fill in the local, non-versioned files
$EDITOR ~/.zshenv.local     # secrets, tokens, proxy (mode 0600)
$EDITOR ~/.gitconfig.local  # git identity, credential helper
```

The repo must stay in place after deployment: `$HOME` symlinks point into it,
`~/.config/mise` among them.

On WSL, the `herd-publish` user unit needs systemd: `systemd=true` under
`[boot]` in `/etc/wsl.conf`, then `wsl --shutdown`. Without it the bootstrap
task skips the unit and says so. On a box with a history, `mise bootstrap` stops
on a real file where a symlink should go; `--force-dotfiles` replaces it.

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
| `mise/config.local.toml` | machine-local tools or env, next to the versioned config | by mise, after `config.toml` |

Secrets go in `~/.zshenv.local`, not `~/.zshrc.local`: a process spawned outside an
interactive shell never reads `.zshrc`, so an export placed there would be invisible
to it. The same file puts the mise shims on PATH, which is what makes every pinned
tool reachable from those processes — MCP servers, `wsl.exe -- herdr`, cron.

The HTTP proxy is opt-in. `.zshrc` exports `http_proxy`/`https_proxy` only when
`_PROXY` is set in `~/.zshenv.local` — a wrong default would break every outbound
call on a network that has none. mise reads the same variables.

Where a password store is available, prefer indirection over literals — see the
commented `pass` example in `.zshenv.local.example`.

## Testing in containers

The whole flow can be exercised against a throwaway container, which is the
only honest way to check what happens on a machine that has never been touched:

```bash
./test/run.sh dotfiles        # `mise bootstrap` twice (no tools), asserts idempotence and what landed
./test/run.sh clis            # packages + `mise install` twice + `mise bootstrap packages upgrade` + `mise run check`
./test/run.sh rollback        # refuses a conflicting file, deploys with --force-dotfiles, rolls back
./test/run.sh wezterm         # installs wezterm and parses the versioned config
./test/run.sh shell           # interactive shell in the test bed
```

The repo is bind-mounted **read-only** and copied inside the container, because
`mise install` writes `mise.lock` next to its config: a `git status` on the copy at
the end is what proves a run changed nothing in the tree, the lock included. The host
proxy variables and `MISE_GITHUB_TOKEN` are carried through.

The base image is selectable, and CI runs the suite across three distros:

```bash
BASE_IMAGE=ubuntu:22.04 ./test/run.sh dotfiles
BASE_IMAGE=fedora:43 ./test/run.sh clis
```

The bootstrap branches on the package manager, and the glibc each release ships
is what the downloaded binaries link against — Ubuntu 22.04 is the oldest one
anything here has to run on. CI also runs the container targets on an `arm64`
runner, on the current Ubuntu LTS only.

What `dotfiles` asserts:

- run 1 completes on a pristine `$HOME` (and installs every tool on the way: `mise run` does)
- run 2 prints no `changed:` line — both runs happen in the **same** container, since a
  fresh one would make any deployment look idempotent
- every symlink and local template lands where expected, `~/.config/mise` included
- the deployed `.zshrc` parses and an interactive zsh loads it with mise on PATH
- the Claude Code hooks are registered, the font is visible to fontconfig, the login shell is zsh
- nothing was written into the repo

What `clis` asserts:

- `mise run install` completes on a machine with none of the tools present, podman, wezterm and vscode included
- a second pass installs nothing — again in the **same** container
- `mise run check` passes: every installed tool answers `--version`, `version` or `--help` with exit 0 (a
  musl build on a host that needs glibc, or a wrong asset picked for the architecture, both download
  perfectly and fail on first use), the lock audit is clean, `mise doctor` reports no problem
- `mise.lock` came out of it unchanged

Caveat: daemons install but do not start in a container. The `chsh` does run — the
test user holds a `NOPASSWD` sudoers entry — and it is part of what the second run
proves.

## Rollback

```bash
make rollback          # = mise run rollback
```

It stops the `herd-publish` unit, takes the five hook events back out of
`~/.claude/settings.json`, unlinks `~/.config/btop/themes`, then `mise dot
unapply` removes every `[dotfiles]` symlink, `~/.config/mise` last. The three
`*.local` files, oh-my-zsh, the fonts and the tools under `~/.local/share/mise`
stay; the tools just leave PATH until a config names them again. System packages
are not removed (`mise bootstrap packages status` lists them).

mise never overwrites a real file where a symlink should go: a first deploy on
a box with history stops and names the conflicts, and `mise bootstrap
--force-dotfiles` is the explicit opt-in to replace them (nothing is backed up:
copy what you want to keep first). The login shell is **not** reverted:
`chsh -s /bin/bash` is the manual step if you want it back.

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
- Debian/Ubuntu, Fedora/RHEL and WSL. The bootstrap refuses any other family rather than failing halfway.
- Daemons install but are not started or enabled — that is left to the machine's owner.
- Ansible is gone. [MIGRATION.md](MIGRATION.md) covers moving a machine it provisioned, and removing it.
