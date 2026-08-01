#!/usr/bin/env bash

##
# Bash completion for ak.sudo.remote-*: position 1 — ssh host aliases,
# position 2 — minute presets (remote-lend only). Bash shows no descriptions,
# so only bare host names are offered.
##

function _ak_sudo_remote_bash() {
  local -r cur="${COMP_WORDS[COMP_CWORD]}"
  COMPREPLY=()

  if (( COMP_CWORD == 1 )); then
    local hosts=''
    hosts="$(ak.ssh.hosts 2> /dev/null)"
    COMPREPLY=( $(compgen -W "${hosts}" -- "${cur}") )
    return 0
  fi

  if (( COMP_CWORD == 2 )) && [[ "${COMP_WORDS[0]}" == 'ak.sudo.remote-lend' ]]; then
    COMPREPLY=( $(compgen -W '15 30 60 120' -- "${cur}") )
  fi
  return 0
}

complete -F _ak_sudo_remote_bash ak.sudo.remote-lend ak.sudo.remote-revoke ak.sudo.remote-status
