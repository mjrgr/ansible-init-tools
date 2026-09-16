ANSIBLE ?= ansible-playbook
LOCAL   := -c local -i localhost,
BECOME  ?= --ask-become-pass

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk -F':.*?## ' '{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ─── Provisioning ────────────────────────────────────────────────────────────

.PHONY: install
install: ## Install the CLI tools (sudo; only what is missing)
	$(ANSIBLE) playbooks/install_clis.yml $(LOCAL) $(BECOME)

.PHONY: upgrade
upgrade: ## Upgrade every CLI tool in place (sudo)
	$(ANSIBLE) playbooks/install_clis.yml $(LOCAL) $(BECOME) -e clis_state=latest

.PHONY: dotfiles
dotfiles: ## Deploy the dotfiles (sudo only to chsh to zsh, once)
	$(ANSIBLE) playbooks/dotfiles.yml $(LOCAL) $(BECOME)

.PHONY: rollback
rollback: ## Remove the dotfiles symlinks and restore the backups
	$(ANSIBLE) playbooks/dotfiles_rollback.yml $(LOCAL)

# ─── Testing ─────────────────────────────────────────────────────────────────

.PHONY: test
test: ## Deploy the dotfiles in a container and assert idempotence (UBUNTU_VERSION=22.04 to switch LTS)
	./test/run.sh dotfiles

.PHONY: test-clis
test-clis: ## Run install_clis.yml twice in a container (ROLE=<name> for one role, single run)
	./test/run.sh clis $(ROLE)

.PHONY: test-rollback
test-rollback: ## Deploy then roll back in a container, assert the restore
	./test/run.sh rollback

.PHONY: test-pins
test-pins: ## Check every pinned tool version still installs
	./test/run.sh pins

.PHONY: drift
drift: ## Report which pinned versions upstream has moved past (needs gh)
	./test/pin-drift.sh

.PHONY: checksums
checksums: ## Refetch every pinned asset and write its sha256 into the role defaults
	./test/checksums.py

.PHONY: checksums-audit
checksums-audit: ## Offline: assert every pinned version carries a sha256
	./test/checksums.py --audit

.PHONY: test-wezterm
test-wezterm: ## Install wezterm in a container and parse the versioned config
	./test/run.sh wezterm

.PHONY: shell
shell: ## Interactive shell in the test bed
	./test/run.sh shell

# ─── Quality ─────────────────────────────────────────────────────────────────

.PHONY: lint
lint: ## yamllint + ansible-lint + syntax check + checksum audit
	yamllint .
	ansible-lint playbooks/
	./test/checksums.py --audit
	@for pb in playbooks/*.yml; do $(ANSIBLE) "$$pb" --syntax-check $(LOCAL) >/dev/null && echo "syntax OK $$pb"; done

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
