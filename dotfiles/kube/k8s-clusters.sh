#!/usr/bin/env bash

K8S_CFG_PATH="$HOME/.kube/"

# Final kubeconfig list
kubeconfigs=()

# Import default kubeconfig if present
DEFAULT_KUBECONFIG_FILE="$K8S_CFG_PATH/config"
if [[ -f "$DEFAULT_KUBECONFIG_FILE" ]]; then
    if [ -s "$DEFAULT_KUBECONFIG_FILE" ];then
        kubeconfigs+=("$DEFAULT_KUBECONFIG_FILE")
    fi    
fi

# Function to collect kubeconfig files from a directory
collect_kubeconfigs() {
    local dir="$1"

    [[ -d "$dir" ]] || return

    # cache/ = discovery+http de kubectl, ~1000 inodes sur 9p (~6.5s) et aucun kubeconfig
    while IFS= read -r -d '' file; do
        kubeconfigs+=("$file")
    done < <(find "$dir" \
        -name cache -prune -o \
        \( -name "*.yml" -o -name "*.yaml" \) \
        -type f -print0)
}

# Collect configs from ~/.kube
collect_kubeconfigs "$K8S_CFG_PATH"

export KUBECONFIG="$(IFS=:; echo "${kubeconfigs[*]}")"
