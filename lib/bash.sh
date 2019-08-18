#!/usr/bin/env bash

#
# Example:
#
#   if ! checkBashVersion 4 3; then
#     echo 'Minimal supported bash version 4.3' >&2
#     exit 1
#   fi
#
function ak.bash.checkBashVersion() {
  local -r MAJOR="${1:-0}"
  local -r MINOR="${2:-0}"
  local -r FIX="${3:-0}"


  if [[ $MAJOR -le 0 ]]; then
    echo 'checkBashVersion: Error: MAJOR version should be specified' >&2
    exit 1
  fi

  if     [[ ${BASH_VERSINFO[0]} -gt ${MAJOR} ]] \
    || ( [[ ${BASH_VERSINFO[0]} -eq ${MAJOR} ]] && [[ ${BASH_VERSINFO[1]} -gt ${MINOR} ]] ) \
    || ( [[ ${BASH_VERSINFO[0]} -eq ${MAJOR} ]] && [[ ${BASH_VERSINFO[1]} -eq ${MINOR} ]] && [[ ${BASH_VERSINFO[2]} -ge ${FIX} ]] )
  then
     return 0
  else
     return 1
  fi
}

function ak.bash.history() {
  local -r phrase="${1}"
  local -r limit="${2:-50}"

  if [[ -z "${phrase}" ]]; then
      echo 'ArgError: No search phrase' >&2
      return 1
  fi

  if [[ "${limit}" -le 0 ]]; then
      echo 'ArgError: limit should greater then 0' >&2
      return 1
  fi

  history \
    | grep "${phrase}" \
    | sort -r -k2 \
    | uniq -f2 \
    | sort -k1 \
    | tail -n ${limit} \
    | grep --color=auto "${phrase}"

  return 0
}

#
# Example:
#
#   if ! ak.bash.commandExists node; then
#     echo 'NodeJS should be installed' >&2
#     exit 1s
#   fi
#
function ak.bash.commandExists() {
  local -r command="${1}";

  if [[ -x "$(which "${command}")" ]]; then
    return 0;
  fi

  return 1;
}

function ak.bash.showConfig() {
  cat "${AK_SCRIPT_PATH}/config.sh" | tail -n +3
}
