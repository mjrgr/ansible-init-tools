# Test bed: a clean distro image with sudo, git (for the tree snapshot) and an unprivileged user, nothing
# else. scripts/bootstrap.sh installs the rest, which is the point: the run
# proves the bootstrap works on a machine that has never been touched.
# BASE_IMAGE is what lets CI run the suite across Ubuntu LTS releases and Fedora.
# The repo is bind-mounted read-only at run time, so the image needs no rebuild
# between iterations and the run proves nothing writes into it.
ARG BASE_IMAGE=ubuntu:26.04
FROM ${BASE_IMAGE}

ARG USERNAME=tester
ENV DEBIAN_FRONTEND=noninteractive

RUN if command -v apt-get >/dev/null; then \
      apt-get update && apt-get install -y --no-install-recommends sudo git locales \
      && locale-gen en_US.UTF-8 && rm -rf /var/lib/apt/lists/*; \
    else \
      dnf install -y sudo git shadow-utils glibc-langpack-en && dnf clean all; \
    fi
ENV LANG=en_US.UTF-8

RUN useradd --create-home --shell /bin/bash "$USERNAME" \
 && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
 && chmod 0440 "/etc/sudoers.d/$USERNAME"

USER $USERNAME
WORKDIR /repo
