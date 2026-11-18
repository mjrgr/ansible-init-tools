# .zshenv — sourced by EVERY zsh shell (interactive or not), before .zshrc.
# Versioned in ansible-init-tools — deployed by `mise run dotfiles`.

# The mise shims: what makes every pinned tool reachable from a shell that
# never reads .zshrc — MCP servers spawned by Claude, `wsl.exe -- herdr` from
# the Windows WezTerm, cron. .zshrc swaps them for the real paths on activate.
[[ -d "$HOME/.local/share/mise/shims" ]] && export PATH="$HOME/.local/share/mise/shims:$PATH"

[[ -s "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Secrets and machine-specific variables.
# Loaded here rather than from .zshrc so it stays available non-interactively:
# MCP servers spawned by Claude do not inherit an interactive shell.
[[ -s "$HOME/.zshenv.local" ]] && . "$HOME/.zshenv.local"
