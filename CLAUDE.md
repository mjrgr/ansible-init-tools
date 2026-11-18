# CLAUDE.md — ansible-init-tools

Bootstrap d'un poste Debian/Ubuntu, Fedora/RHEL ou WSL (x86_64/aarch64) : `scripts/bootstrap.sh` (sudo : paquets de base,
podman, wezterm, vscode, binaire mise pinné ; `--upgrade` ne remonte que ses propres paquets) puis **tout le reste par mise** —
outils pinnés (`mise/config.toml` + `mise.lock`), `[env]`, et tâches de dotfiles (symlinks vers le repo, sans sudo sauf `chsh`).
Le bootstrap est aussi une tâche (`mise run bootstrap`, wrapper `sudo` + `raw=true`) : une seule UX après le premier run, qui est
forcément `make setup` (prérequis `git make`, car `mise run` installe les outils avant toute tâche et rust a besoin du toolchain
du bootstrap). Plus aucun Ansible ; `MIGRATION.md` pour un poste provisionné par l'ancien setup.

## Layout (non évident)

- `mise/config.toml` : config **globale** — `mise run dotfiles:mise` symlinke `~/.config/mise` → `mise/`, donc `[tools]`, `[env]`
  et les tâches s'appliquent partout. Depuis le clone sans ce lien, c'est une config projet (`mise trust` requis).
- `mise/mise.lock` : URLs + sha256 par outil pour `linux-x64` et `linux-arm64` (`lockfile_platforms`). Jamais édité à la main :
  `make lock` ; `make lock-audit` (offline) exige les deux plateformes avec digest, sauf backends `core:`/`cargo:` (rustup/cargo vérifient).
- `[tool_alias]` : noms courts pour les outils hors registry (`github:`) ou réassignés (`helmfile`, `neovim`). Deux outils d'une même
  release (codex / codex-code-mode-host, kwok / kwokctl, krew) = alias + `matching_regex` ; jamais `asset_pattern` templaté
  (le lock fige l'asset rendu sur l'hôte, donc amd64 pour arm64).
- aqua d'abord (URL de release directe, checksums/cosign/SLSA du registry) ; `github:` seulement sans entrée registry — il passe par
  `api.github.com` (quota anonyme 60/h) → `MISE_GITHUB_TOKEN` en CI et derrière un proxy partagé.
- `mise/tasks/` : file tasks auto-découvertes (`bootstrap`, `dotfiles/<group>` = `mise run dotfiles:<group>`, `krew-plugins`,
  `rollback`). Chaque script (sauf `bootstrap`) source `scripts/lib/dotfiles.sh` (`REPO` via `readlink -f $0`, `link_dotfile` backup+symlink, `changed` = seul signal de
  changement). cwd d'une tâche = `$HOME` (config root global), pas le repo.
- `scripts/lib/claude-settings.py` : merge/strip des hooks et chaînage statusLine dans `~/.claude/settings.json` (fichier de l'utilisateur,
  jamais templaté). Par event, seule l'entrée dont la commande contient le basename du script est à nous (`is_ours`) : les autres
  (herdr, context-mode…) restent, à l'enregistrement comme au rollback ; un fichier déjà à jour ressort identique. `scripts/uninstall-ansible.sh`, `scripts/cleanup-legacy.sh` : dry-run par défaut, `--yes` pour appliquer.
- `dotfiles/` : sources versionnées, liées (pas copiées) dans `$HOME`. `*.local` gitignorés, seuls les `*.local.example` sont versionnés.
  `.zshenv` met les shims mise sur PATH (shells non interactifs : MCP, `wsl.exe -- herdr`, unit systemd) ; `.zshrc` active mise **avant**
  OMZ, car tous les `command -v` qui suivent en dépendent.
- `mise/tasks/rollback` : liste **autoritative** `links` ; `EVENTS` de `claude-settings.py` pour les hooks Claude.
- `test/` : `run.sh` (banc conteneur, repo monté `:ro` puis copié ; `BASE_IMAGE=ubuntu:22.04|fedora:43`), `Dockerfile` (sudo + git +
  user, le bootstrap fait le reste), `lock-audit.py`.

## Commandes

```bash
make lint                 # shellcheck + yamllint + parse config mise + lock-audit
make setup                # premier run : bootstrap (sudo) + trust + install + dotfiles ; ensuite `mise run setup`
make bootstrap            # scripts/bootstrap.sh  (ARGS="--skip podman,wezterm,vscode" | "--upgrade") = mise run bootstrap
make install | bump       # mise run install (lock + krew plugins) | mise upgrade --bump (réécrit config + lock, installe)
make upgrade              # bootstrap --upgrade (sudo, paquets du bootstrap seulement) + bump = mise run upgrade
make bump-mise            # pin mise (version + sha256 x64/arm64) dans scripts/bootstrap.sh → latest (VERSION=vX pour choisir), puis make bootstrap
make dotfiles | rollback  # mise run dotfiles | mise run rollback
mise run dotfiles:starship                      # un seul groupe
mise install kubectl helm                        # deux outils
make test                 # bootstrap + dotfiles x2 en conteneur ; 2e run = aucune ligne "changed:" (BASE_IMAGE pour changer d'OS)
make test-clis            # bootstrap complet + mise run install x2 + `mise run bootstrap -- --upgrade` (doit ne rien remonter) ;
                          # chaque outil doit répondre --version|version|--help ; lock inchangé
make test-rollback | test-wezterm | shell
make lock | lock-audit    # régénère mise.lock | audit offline
make drift                # mise outdated
make scan | hooks         # gitleaks (image pinnée par digest) ; hooks = core.hooksPath .githooks
```

`mise run` installe les outils manquants avant d'exécuter une tâche : `make test` installe donc aussi les 59 outils.

Pas de `--check` : valider en conteneur. `mise lock` et `mise install` ont besoin du réseau ; `mise.lock` doit être en 0644 (mise
l'écrit en 0600, le conteneur ne le lirait pas).

## Conventions

- Pins concrets partout ; `claude = "latest"` est l'exception (figé par le lock, `mise upgrade claude`).
- Une tâche imprime `changed: …` pour chaque action réelle et rien sinon — c'est l'assertion d'idempotence du banc.
- Tâche interactive (`chsh`) : `#MISE raw=true`. Dépendances : `#MISE depends=["dotfiles:common"]`.
- Outil qui a besoin d'un paquet système (linker, lib) → `scripts/bootstrap.sh`, branché apt/dnf, jamais dans mise.
- `command-instead-of-shell`-like : tout `curl` passe par `fetch_if_changed` ou vérifie un sha256 ; pas de `curl | sh` non pinné sauf
  l'installeur oh-my-zsh (comportement historique, `creates`-guardé).
- yamllint ne couvre plus que `.github/` (`truthy.check-keys: false` pour `on:`).

## Ajouter un outil

1. Entrée dans `[tools]` de `mise/config.toml` (`mise ls-remote <tool>` pour la version ; registry = `mise registry | grep`). Hors registry :
   alias `github:owner/repo` + `matching_regex` couvrant amd64 **et** arm64.
2. `make lock` puis `make lock-audit` et `make lint`.
3. `make test-clis` (ou `mise install <tool>` + `<tool> --version` sur les deux archs en CI).
4. Table « Included CLIs » du README ; `scripts/cleanup-legacy.sh` si l'outil avait une copie Ansible sous `/usr/local/bin`.

## Ajouter un dotfile

Source sous `dotfiles/<group>/`, tâche `mise/tasks/dotfiles/<group>` (source `dotfiles.sh`, `link_dotfile`), groupe dans `depends` de
`[tasks.dotfiles]`, répertoire cible dans `dotfiles/common` si nouveau, **et** chemin dans `links` de `mise/tasks/rollback` — sinon le
rollback ne le restaure pas. Nouvel event de hook Claude → `EVENTS` + `hooks_for` dans `claude-settings.py`.

## CI (`.github/workflows/ci.yml`)

push `main`, PR, `workflow_dispatch`, cron lundi 06:17 UTC. Actions pinnées par SHA (Dependabot `github-actions` uniquement).
`MISE_GITHUB_TOKEN: ${{ github.token }}` global. Jobs : `lint`, `secrets` (gitleaks historique), `dotfiles`/`rollback`/`clis`
(ubuntu 22.04, 26.04, fedora 43, 26.04 arm64), `wezterm-config`. Hors gate : `lock-drift` (cron/dispatch : `mise lock` puis
`git diff --exit-code`) et `pin-drift` (hors PR, `mise outdated --json`, issue unique label `pin-drift`).

## Pièges

- Lock généré sur un hôte : `mise lock` résout **toutes** les plateformes de `lockfile_platforms` ; un `matching_regex` qui n'en couvre
  qu'une fait échouer le lock entier.
- GitHub 500/403 transitoires sur `mise lock` : relancer (403 = quota API → token).
- `mise upgrade --bump` réécrit `config.toml` **avant** le lock : s'il échoue sur un outil, les autres pins sont bumpés sans lock
  (lock-audit le signale) → `make lock` puis `make test-clis`. Sur l'hôte migré, `~/.config/mise` → repo = config globale :
  `make lock` passe `--global` tout seul.
- `aqua.baked_registry = true` : mise embarque le registry aqua de sa date de build. Un fix registry plus récent (vu : kyverno 1.20.0,
  nouveau workflow signataire, cosign refuse au lock) n'est visible qu'avec une mise buildée après → `make bump-mise` puis
  `make bootstrap`. Sinon l'outil va dans `BUMP_EXCLUDE` (Makefile, et `--exclude` dans `[tasks.upgrade]`) le temps que mise suive.
- `sudo mise …` (self-update, install) : sudo nu perd le proxy → timeouts sur mise.jdx.dev/GitHub. mise n'est jamais mis à jour par
  `self-update` : c'est le pin du bootstrap qui compte, et `mise run bootstrap` porte le proxy.
- `mise run` cwd = `$HOME` : chemins relatifs interdits dans les tâches, tout passe par `$REPO`/`$DOTFILES`.
- Les outils sont par utilisateur : `sudo kubectl` ne les voit pas (`sudo env "PATH=$PATH" …`).
- WSL : `~/.kube` peut être un drvfs (chmod → EPERM) ; ne jamais réimposer un `mode` sur un répertoire existant. Unit systemd user
  → `systemd=true` dans `/etc/wsl.conf`.
- Les démons (podman…) sont installés, jamais démarrés ni activés.
- Ubuntu 22.04 (glibc 2.35) est la plus vieille cible : un binaire qui ne tourne pas dessus casse `test-clis`.
