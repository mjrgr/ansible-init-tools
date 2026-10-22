# CLAUDE.md — ansible-init-tools

Bootstrap d'un poste Debian/Ubuntu (WSL2 ou natif, x86_64/aarch64) en `localhost`/`-c local` :
CLIs système (`install_clis.yml`, sudo) + dotfiles en symlinks vers le repo (`dotfiles.yml`, sans sudo sauf `chsh`).
Les deux playbooks refusent de tourner hors apt et hors x86_64/aarch64.

## Layout (non évident)

- `playbooks/roles/<tool>/` : un rôle par CLI ; nom du rôle = entrée de `install_list` = tag = préfixe des variables.
- `playbooks/roles/clis_common/tasks/` : bibliothèque partagée, jamais exécutée seule — `resolve.yml` → `probe.yml` → `install_binary.yml` | `install_archive.yml`.
- `playbooks/roles/dotfiles_<group>/` : un rôle par groupe de `dotfiles_list` ; `dotfiles_common/tasks/link.yml` fait backup + symlink.
- `dotfiles/` : sources versionnées, liées (pas copiées) dans `$HOME`. `*.local` gitignorés, seuls les `*.local.example` sont versionnés.
- `playbooks/dotfiles_rollback.yml` : liste **autoritative** `dotfiles_links` + `rb_claude_hook_events`.
- `test/` : `run.sh` (banc Docker Ubuntu, repo monté en `:ro`), `checksums.py`, `pin-drift.sh`, `bump-pins.sh`, `Dockerfile`.
- Variables de play (`install_list`, `common_packages`, `clis_state`, `dotfiles_list`…) dans les playbooks eux-mêmes ; pas de `group_vars`, pas de `vars/` dans les rôles.

## Commandes

```bash
make lint                 # yamllint + ansible-lint playbooks/ + checksums --audit + --syntax-check
make install | upgrade    # install_clis.yml (-K) ; upgrade = -e clis_state=latest
make dotfiles | rollback
ansible-playbook playbooks/install_clis.yml -c local -i localhost, -K -e install_only=k9s
ansible-playbook playbooks/install_clis.yml -c local -i localhost, -K --tags kubectl,helm
ansible-playbook playbooks/dotfiles.yml -c local -i localhost, --tags starship   # ou -e dotfiles_only=starship
make test                 # dotfiles x2 en conteneur, 2e run doit être changed=0 (UBUNTU_VERSION=22.04 pour l'autre LTS)
make test-clis [ROLE=x]   # install_clis x2 ; assertion = aucun "-> install" au 2e run (pas changed=0)
make test-rollback | test-pins | test-wezterm | shell
make checksums [ROLE]     # recalcule les sha256 dans defaults ; jamais de digest copié à la main
make drift | bump-pins    # écart pins vs upstream (gh requis) ; bump-pins modifie le working tree, ne commit pas
make scan | hooks         # gitleaks (image pinnée par digest) ; hooks = core.hooksPath .githooks
```

`--check --diff` : non outillé pour `install_clis.yml` — `probe.yml` est un `shell` sans `check_mode: false`, son `rc` manquera en check mode (à confirmer). Seul `dotfiles_herdr` porte des `check_mode: false` explicites. Valider plutôt en conteneur (`make test*`).

Tags : un tag par outil / groupe (`apply.tags`), plus `common` (paquets apt de base), `tools`, `dotfiles`, `always` (garde-fous, `set_fact` de sélection).

## Conventions des rôles CLI

- Rôle binaire : `defaults/main.yml` = `<role>_version` (tag concret, pinné), `<role>_arch` (`{amd64,arm64}` → slug upstream), `<role>_url` (placeholders `{version}`, `{version_nov}`, `{arch}`), `<role>_sha256` par arch.
- `meta/argument_specs.yml` obligatoire pour ces rôles (valide les overrides à l'include). Les rôles apt (gh, jq, podman, vscode, wezterm) n'en ont pas.
- Idempotence = probe de version (`clis_need_install`) : `present` n'installe que si absent ou version ≠ pin ; `latest` réinstalle tout. Apt : `state: "{{ 'latest' if clis_state == 'latest' else 'present' }}"`.
- Les faits `clis_*` sont volontairement non préfixés → `# noqa: var-naming[no-role-prefix]` ; les autres variables/`register` sont préfixées par le rôle.
- Install sous `/usr/local/bin`, `get_url` avec `checksum`, `retries: 5 / delay: 5`, puis un `--version` (ou `clis_verify_cmd`) prouve que le binaire tourne.
- Sources apt : keyring dans `/etc/apt/keyrings`, `signed-by`, source supprimée puis recréée → `changed` à chaque run **par design** (gh, vscode, wezterm).
- `command-instead-of-shell` et `no-changed-when` sont skip dans `.ansible-lint` : tout `shell`/`command` doit quand même porter `changed_when` ou `creates`/`removes`.
- yamllint : pas de `---` exigé sur les plays, truthy `true|false` seulement, octal implicite interdit, lignes > 160 = warning.

## Ajouter un outil

1. `playbooks/roles/<tool>/{defaults,meta,tasks}` en copiant un rôle du même type (`k9s` archive, `kubectl`/`yq` binaire, `jq`/`gh` apt).
2. `tasks/main.yml` : `include_tasks: "{{ role_path }}/../clis_common/tasks/resolve.yml"` puis `probe.yml`, puis install avec `when: clis_need_install | bool`. `clis_name` identique sur les trois includes (garde `clis_resolved_for`).
3. Ajouter `<tool>` à `install_list` dans `playbooks/install_clis.yml`.
4. `make checksums ROLE=<tool>` puis `make lint` et `make test-clis ROLE=<tool>`.
5. Upstream hors github.com : ajouter l'entrée dans `UPSTREAM` de `test/pin-drift.sh` **et** `test/bump-pins.sh`. `test-pins`/`drift` découvrent le rôle seuls via `<role>_version`.
6. Mettre à jour la table « Included CLIs » du README.

## Ajouter un dotfile

Source sous `dotfiles/<group>/`, rôle `dotfiles_<group>` qui inclut `link.yml` (`loop_var: dl`), groupe dans `dotfiles_list`,
répertoire cible dans `dotfiles_common_dirs` si nouveau, **et** chemin dans `dotfiles_links` de `dotfiles_rollback.yml` — sinon le rollback ne le restaure pas.
Nouvel event de hook Claude dans `dotfiles_wezterm_claude_hooks` → le reporter dans `rb_claude_hook_events`.

## CI (`.github/workflows/ci.yml`)

push `main`, PR, `workflow_dispatch`, cron lundi 06:17 UTC. Actions pinnées par SHA (Dependabot `github-actions` uniquement).
Jobs : `lint`, `secrets` (gitleaks sur l'historique), `checksum-audit`, `dotfiles`/`rollback`/`pins` (22.04 + 26.04 + 26.04 arm64), `clis` (26.04 amd64/arm64), `wezterm-config`.
Hors gate : `checksum-drift` (cron/dispatch, re-télécharge tout) et `pin-drift` (hors PR, tient une issue unique label `pin-drift`).

## Pièges

- Ansible-core diffère par LTS (2.12 sur 22.04, 2.16 sur 26.04) : tester les deux avant de conclure.
- Ubuntu ≥ 25.10 : `sudo-rs` casse `--ask-become-pass` (timeout become) — voir README.
- Proxy : `sudo` strippe l'env, `install_clis.yml` réinjecte `HTTP(S)_PROXY`/`NO_PROXY` via `environment` ; `test/run.sh` les propage au conteneur.
- `include_role` en boucle : `loop_var` explicite (`clis_tool`, `dotfiles_group`), `item` entre en collision avec les boucles des rôles.
- WSL : `~/.kube` peut être un symlink vers drvfs (chmod → EPERM) ; ne jamais réimposer un `mode` sur un répertoire existant.
- Pas de `cache_valid_time` sur l'apt de base (lists purgées mais mtime récent) ; l'échec de cache est diagnostiqué par le `rescue`.
- `ansible.cfg` : log dans `/tmp/ansible-clis.log`. Lint CI installe `ansible-lint`/`yamllint` non pinnés (pipx/pip).
- Les démons (podman…) sont installés, jamais démarrés ni activés.
