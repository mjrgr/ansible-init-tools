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

# Base64 hardcoded: this runs on every command, and _wt_user_var would fork base64
_wt_busy() { printf '\033]1337;SetUserVar=busy=%s\007' "$1" }

# Pure zsh, no git fork per prompt: walks up to the nearest .git and reads HEAD.
# A worktree's .git is a file pointing at the real gitdir; detached HEAD gives ''.
_wt_git_branch() {
  local dir=$PWD gitdir head
  REPLY=
  while [[ -n $dir ]]; do
    if [[ -d $dir/.git ]]; then
      gitdir=$dir/.git; break
    elif [[ -f $dir/.git ]]; then
      gitdir=$(<$dir/.git); gitdir=${gitdir#gitdir: }
      [[ $gitdir == /* ]] || gitdir=$dir/$gitdir
      break
    fi
    dir=${dir%/*}
  done
  [[ -n $gitdir && -r $gitdir/HEAD ]] || return 0
  head=$(<$gitdir/HEAD)
  [[ $head == ref:\ refs/heads/* ]] && REPLY=${head#ref: refs/heads/}
}

zmodload zsh/datetime
typeset -g _wt_ran=0

_wt_precmd() {
  local rc=$?
  printf '\033]133;D;%s\007\033]133;A\007' "$rc"
  _wt_busy ''
  # Only after a real command: Ctrl+C on an empty prompt also lands here, with rc 130.
  # The timestamp makes each failure distinct, so the tab bar can tell a new one
  # from one it has already shown.
  if (( _wt_ran )); then
    _wt_ran=0
    if (( rc != 0 )); then
      _wt_user_var last_fail "$EPOCHSECONDS:$rc"
    else
      _wt_user_var last_fail ''
    fi
  fi
  _wt_user_var kube_ctx "$(_wt_kube_context)"
  _wt_git_branch; _wt_user_var git_branch "$REPLY"
  _wt_user_var is_root "$(( EUID == 0 ))"
  _wt_user_var distro "$_wt_distro"
}

_wt_preexec() {
  printf '\033]133;C\007'
  _wt_busy MQ==
  _wt_ran=1
}

# Local-side marker, like the claude wrapper in ~/.zshrc: the remote shell has none
# of this. The host is the first argument that is neither an option nor the value
# of one, so `ssh -p 2222 -i key user@host cmd` yields `host`.
ssh() {
  local host= prev= arg
  for arg in "$@"; do
    if [[ -n $prev ]]; then prev=; continue; fi
    if [[ $arg == -* ]]; then
      [[ $arg == -[bcDEeFIiJLlmOopQRSWwBP] ]] && prev=$arg
      continue
    fi
    host=${arg#*@}; break
  done
  _wt_user_var ssh_host "$host"
  command ssh "$@"
  local rc=$?
  _wt_user_var ssh_host ''
  return $rc
}

add-zsh-hook precmd _wt_precmd
add-zsh-hook preexec _wt_preexec
