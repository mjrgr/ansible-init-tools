
# 📥 Ansible init Tools 🧰

An Ansible project for installing a collection of CLI tools on **Ubuntu / Debian** (local machine).

### Features
- ✅ Self-contained (no external Galaxy roles required)
- ✅ Prefers package manager installs where sensible, otherwise downloads official latest binaries/scripts
- ✅ Installs "latest available" using vendor-provided "latest" endpoints or installers when available

## Included CLIs / utilities
- kubectl, helm, kind, kwok, k9s, krew, helmfile
- docker, podman, nerdctl, crictl
- awscli, terraform
- yq, jq
- git, make, curl, wget, gnupg, unzip

## Usage
Run locally (sudo will be used by the playbook):
```bash
ansible-playbook playbooks/install_clis.yml -c local --ask-become-pass
```

If you want to run a single role only (example: install kubectl):
```bash
ansible-playbook playbooks/install_clis.yml -e "install_only=kubectl" -c local --ask-become-pass
```

## Notes
- Some tools rely on vendor install scripts or latest release endpoints; the script approach is used for simplicity and to obtain latest releases.
- Review the role tasks in `roles/` if you want to pin versions or change install methods.
