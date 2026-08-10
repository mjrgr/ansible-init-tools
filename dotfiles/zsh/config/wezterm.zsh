# WezTerm integration: OSC 133 (semantic zones) + user vars for the tab bar.
# OSC 7 (cwd) is already emitted by oh-my-zsh/lib/termsupport.zsh — do not duplicate.

[[ "$TERM_PROGRAM" == "WezTerm" ]] || return 0

autoload -Uz add-zsh-hook

_wt_user_var() {
  local name=$1 val=$2
  local cache="_wt_uv_$name"
  [[ "${(P)cache}" == "$val" ]] && return 0
  typeset -g "$cache=$val"
  printf '\033]1337;SetUserVar=%s=%s\007' "$name" "$(print -rn -- "$val" | base64 | tr -d '\n')"
}

# kubectl merge rule: first non-empty current-context across the KUBECONFIG list
_wt_kube_context() {
  local f ctx
  for f in ${(s.:.)${KUBECONFIG:-$HOME/.kube/config}}; do
    [[ -r $f ]] || continue
    ctx=$(sed -n 's/^current-context: *//p' "$f" | head -1)
    ctx=${ctx//[\"\']/}
    [[ -n $ctx ]] && { print -rn -- "$ctx"; return 0 }
  done
}

# Read once: /etc/os-release does not change during a session
_wt_distro="$(sed -n 's/^ID=//p' /etc/os-release 2>/dev/null | tr -d '"' | head -1)"
: "${_wt_distro:=linux}"

_wt_precmd() {
  local rc=$?
  printf '\033]133;D;%s\007\033]133;A\007' "$rc"
  _wt_user_var kube_ctx "$(_wt_kube_context)"
  _wt_user_var distro "$_wt_distro"
}

_wt_preexec() { printf '\033]133;C\007' }

add-zsh-hook precmd _wt_precmd
add-zsh-hook preexec _wt_preexec
