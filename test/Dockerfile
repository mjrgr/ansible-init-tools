# Test bed for the playbooks: a clean Ubuntu with ansible and an unprivileged user.
# zsh/git/curl are baked in because install_clis.yml provides them on a real host;
# dotfiles.yml checks for them up front and refuses to run otherwise.
# The repo itself is bind-mounted read-only at run time, so the image does not need
# a rebuild between iterations and the run proves the playbooks never write to it.
FROM ubuntu:24.04

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
