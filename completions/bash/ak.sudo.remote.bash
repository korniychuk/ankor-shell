#!/usr/bin/env bash

##
# Bash completion for ak.sudo.remote-*: position 1 — ssh host aliases,
# position 2 — minute presets (remote-lend only). Bash shows no descriptions,
# so only bare host names are offered.
#
# ak.sudo.remote-lend-many: position 1 — minute presets AND hosts, positions
# ≥ 2 — hosts not typed yet (nothing is completed after a comma).
##

# Echo the ssh host aliases minus those already typed on the command line
# (words 1..COMP_CWORD-1, comma-joined words split).
function __ak_sudo_remote_bash_untyped_hosts() {
  local typed=' ' word='' host=''
  for word in "${COMP_WORDS[@]:1:COMP_CWORD-1}"; do
    typed+="${word//,/ } "
  done
  while IFS= read -r host; do
    [[ -z "${host}" || "${typed}" == *" ${host} "* ]] && continue
    printf '%s\n' "${host}"
  done < <(ak.ssh.hosts 2> /dev/null)
}

function _ak_sudo_remote_bash() {
  local -r cur="${COMP_WORDS[COMP_CWORD]}"
  local -r minutePresets='15 30 60 120'
  COMPREPLY=()

  # *-many: hosts not typed yet at every position; lend-many also offers the
  # minute presets at position 1.
  if [[ "${COMP_WORDS[0]}" == 'ak.sudo.remote-lend-many' || "${COMP_WORDS[0]}" == 'ak.sudo.remote-revoke-many' ]]; then
    local words=''
    words="$(__ak_sudo_remote_bash_untyped_hosts)"
    [[ "${COMP_WORDS[0]}" == 'ak.sudo.remote-lend-many' ]] && (( COMP_CWORD == 1 )) && words="${minutePresets} ${words}"
    mapfile -t COMPREPLY < <(compgen -W "${words}" -- "${cur}")
    return 0
  fi

  if (( COMP_CWORD == 1 )); then
    local hosts=''
    hosts="$(ak.ssh.hosts 2> /dev/null)"
    mapfile -t COMPREPLY < <(compgen -W "${hosts}" -- "${cur}")
    return 0
  fi

  if (( COMP_CWORD == 2 )) && [[ "${COMP_WORDS[0]}" == 'ak.sudo.remote-lend' ]]; then
    mapfile -t COMPREPLY < <(compgen -W "${minutePresets}" -- "${cur}")
  fi
  return 0
}

complete -F _ak_sudo_remote_bash ak.sudo.remote-lend ak.sudo.remote-revoke ak.sudo.remote-status \
  ak.sudo.remote-lend-many ak.sudo.remote-revoke-many
