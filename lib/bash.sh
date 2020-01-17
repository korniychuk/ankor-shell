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
