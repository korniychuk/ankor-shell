#!/usr/bin/env bash

# TODO: Split bash to shell + bash/zsh

#
# TODO: Implement normalize boolean function '', 0, false, null
#   - https://unix.stackexchange.com/questions/185670/what-is-a-best-practice-to-represent-a-boolean-value-in-a-shell-script
#   - https://www.google.com/search?q=bash+falsy+values&oq=bash+falsy+values&aqs=chrome..69i57j0.4094j0j4&sourceid=chrome&ie=UTF-8
#

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

  if [[ -x "$(command -v "${command}")" ]]; then
    return 0;
  fi

  return 1;
}

function ak.bash.showConfig() {
  cat "${AK_SCRIPT_PATH}/config.sh" | tail -n +3
}
