.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ─── Provisioning ────────────────────────────────────────────────────────────

.PHONY: setup
setup: ## Fresh box, the whole thing: bootstrap (sudo), trust, every tool, dotfiles
	scripts/bootstrap.sh
	mise trust -q mise/config.toml
	mise run install
	mise run dotfiles

.PHONY: bootstrap
bootstrap: ## System packages, podman, wezterm, vscode and the mise binary (sudo; ARGS="--skip podman,wezterm,vscode")
	scripts/bootstrap.sh $(ARGS)

.PHONY: install
install: ## Install every pinned tool from mise.lock
	mise trust -q mise/config.toml
	mise run install

.PHONY: upgrade
upgrade: ## Owned system packages to their latest (sudo), every pin to upstream's latest, then check
	mise run upgrade

.PHONY: bump
bump: ## Only the pins: move each to upstream's latest, refresh mise.lock, install (edits mise/config.toml)
	mise run bump

.PHONY: check
check: ## This host: every tool answers, lock audited, mise doctor clean, herd-publish unit up
	mise run check

.PHONY: bump-mise
bump-mise: ## Move the mise pin in scripts/bootstrap.sh to the latest release (VERSION=v2026.11.9 to pick one), then `make bootstrap`
	scripts/bump-mise.sh $(VERSION)

.PHONY: dotfiles
dotfiles: ## Deploy the dotfiles (asks your password once, to chsh to zsh)
	mise trust -q mise/config.toml
	mise run dotfiles

.PHONY: rollback
rollback: ## Remove the dotfiles symlinks and restore the backups
	mise run rollback

# ─── Testing ─────────────────────────────────────────────────────────────────

.PHONY: test
test: ## Bootstrap + dotfiles twice in a container, assert the second run changes nothing (BASE_IMAGE=fedora:43 to switch)
	./test/run.sh dotfiles

.PHONY: test-clis
test-clis: ## Bootstrap + mise install twice + bootstrap --upgrade in a container, assert every tool runs and nothing reinstalls
	./test/run.sh clis

.PHONY: test-rollback
test-rollback: ## Deploy then roll back in a container, assert the restore
	./test/run.sh rollback

.PHONY: test-wezterm
test-wezterm: ## Install wezterm in a container and parse the versioned config
	./test/run.sh wezterm

.PHONY: shell
shell: ## Interactive shell in the test bed
	./test/run.sh shell

.PHONY: drift
drift: ## Report which pins upstream has moved past
	mise outdated

# Once ~/.config/mise links here, mise reads mise/config.toml as the global
# config, and a bare `mise lock` finds no project to lock.
LOCK_SCOPE := $(shell [ "$$(readlink -f ~/.config/mise 2>/dev/null)" = "$$(readlink -f mise)" ] && echo --global)

.PHONY: lock
lock: ## Refresh mise.lock (URLs and sha256 for linux x64/arm64) after editing a pin
	mise lock $(LOCK_SCOPE)

.PHONY: lock-audit
lock-audit: ## Offline: assert every tool is locked for both platforms with a checksum
	./test/lock-audit.py

# ─── Quality ─────────────────────────────────────────────────────────────────

.PHONY: lint
lint: ## shellcheck + yamllint + mise config parse + lock audit
	shellcheck -S warning scripts/*.sh scripts/lib/dotfiles.sh test/run.sh mise/tasks/bootstrap mise/tasks/check mise/tasks/rollback mise/tasks/dotfiles/*
	yamllint .
	python3 -m py_compile scripts/lib/claude-settings.py test/lock-audit.py
	mise --cd mise tasks ls >/dev/null && echo "mise config OK"
	./test/lock-audit.py

# Pinned by digest, like the actions in CI: :latest is a moving target that runs
# with a bind mount of the whole repo.
.PHONY: scan
scan: ## Scan the working tree and history for secrets
	docker run --rm -v "$(PWD):/repo" \
	  ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:b109bc5f8f76a38196a3e413704fc5b9e3c32360bce4e4b603bd6f45b3721dbb \
	  detect --source /repo --config /repo/.gitleaks.toml --redact --verbose

.PHONY: hooks
hooks: ## Enable the repo's git hooks (pre-commit secret scan)
	git config core.hooksPath .githooks
	@echo "core.hooksPath -> .githooks"
