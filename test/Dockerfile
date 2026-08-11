# Test bed for the playbooks: a clean Ubuntu with ansible and an unprivileged user.
# zsh/git/curl are baked in because install_clis.yml provides them on a real host;
# dotfiles.yml checks for them up front and refuses to run otherwise.
# UBUNTU_VERSION is what lets CI run the same suite across LTS releases: the apt
# ansible-core differs per release (2.12 on 22.04, 2.16 on 26.04) and they do not
# behave identically.
# The repo itself is bind-mounted read-only at run time, so the image does not need
# a rebuild between iterations and the run proves the playbooks never write to it.
ARG UBUNTU_VERSION=26.04
FROM ubuntu:${UBUNTU_VERSION}

ARG USERNAME=tester

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ansible-core \
      sudo git curl wget ca-certificates gnupg unzip locales \
      python3 python3-apt \
      zsh fontconfig \
 && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8

RUN useradd --create-home --shell /bin/bash "$USERNAME" \
 && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
 && chmod 0440 "/etc/sudoers.d/$USERNAME"

USER $USERNAME
WORKDIR /repo
