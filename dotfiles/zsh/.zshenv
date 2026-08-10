# .zshenv — sourced by EVERY zsh shell (interactive or not), before .zshrc.
# Versioned in ansible-init-tools.

[[ -s "$HOME/.cargo/env" ]] && . "$HOME/.cargo/env"

# Secrets and machine-specific variables.
# Loaded here rather than from .zshrc so it stays available non-interactively:
# MCP servers spawned by Claude do not inherit an interactive shell.
[[ -s "$HOME/.zshenv.local" ]] && . "$HOME/.zshenv.local"
