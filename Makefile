ANSIBLE ?= ansible-playbook
LOCAL   := -c local -i localhost,

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ─── Provisioning ────────────────────────────────────────────────────────────

.PHONY: install
install: ## Install the CLI tools (sudo; only what is missing)
	$(ANSIBLE) playbooks/install_clis.yml $(LOCAL) --ask-become-pass

.PHONY: upgrade
upgrade: ## Upgrade every CLI tool in place (sudo)
	$(ANSIBLE) playbooks/install_clis.yml $(LOCAL) --ask-become-pass -e clis_state=latest

.PHONY: dotfiles
dotfiles: ## Deploy the dotfiles (no sudo)
	$(ANSIBLE) playbooks/dotfiles.yml $(LOCAL)

.PHONY: rollback
rollback: ## Remove the dotfiles symlinks and restore the backups
	$(ANSIBLE) playbooks/dotfiles_rollback.yml $(LOCAL)

# ─── Testing ─────────────────────────────────────────────────────────────────

.PHONY: test
test: ## Deploy the dotfiles in a container and assert idempotence (UBUNTU_VERSION=22.04 to switch LTS)
	./test/run.sh dotfiles

.PHONY: test-clis
test-clis: ## Run install_clis.yml in a container (ROLE=<name> for one role)
	./test/run.sh clis $(ROLE)

.PHONY: test-rollback
test-rollback: ## Deploy then roll back in a container, assert the restore
	./test/run.sh rollback

.PHONY: test-pins
test-pins: ## Check every pinned tool version still installs
	./test/run.sh pins

.PHONY: test-wezterm
test-wezterm: ## Install wezterm in a container and parse the versioned config
	./test/run.sh wezterm

.PHONY: shell
shell: ## Interactive shell in the test bed
	./test/run.sh shell

# ─── Quality ─────────────────────────────────────────────────────────────────

.PHONY: lint
lint: ## yamllint + ansible-lint + syntax check
	yamllint .
	ansible-lint playbooks/
	@for pb in playbooks/*.yml; do $(ANSIBLE) "$$pb" --syntax-check $(LOCAL) >/dev/null && echo "syntax OK $$pb"; done

.PHONY: scan
scan: ## Scan the working tree and history for secrets
	docker run --rm -v "$(PWD):/repo" ghcr.io/gitleaks/gitleaks:latest \
	  detect --source /repo --config /repo/.gitleaks.toml --redact --verbose

.PHONY: hooks
hooks: ## Enable the repo's git hooks (pre-commit secret scan)
	git config core.hooksPath .githooks
	@echo "core.hooksPath -> .githooks"
