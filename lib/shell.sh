#!/usr/bin/env bash

#
# Shell independent command.
# This commands should works in any shell.
#
# Notice: 'SH' the function names means a shortcut of 'Shell'. It doesn't mean this commands for legasy shell - 'SH'
#

#
# Notice: This library doesn't work in SH.
# TODO: Investigate, is there any existing solutions
#
# @example
#
#   if [[ "$(ak.sh.type)" == 'zsh' ]]; then
#     echo "I'm ZSH!"
#   fi
#
function ak.sh.type() {
  if   [[ -n "${ZSH_VERSION+x}"  ]];                                  then echo 'zsh';
  elif [[ -n "${BASH_VERSION+x}" ]];                                  then echo 'bash';
  else                                                                     echo 'unknown';
  fi
}

#
# @example
#
#   if ak.sh.isZsh; then
#     echo "I'm ZSH!"
#   fi
#
function ak.sh.isZsh() {
  test "$(ak.sh.type)" "==" "zsh"
  return $?
}

function ak.sh.isBash() {
  test "$(ak.sh.type)" "==" "bash"
  return $?
}

function ak.sh.isUnknown() {
  test "$(ak.sh.type)" "==" "unknown"
  return $?
}

#
# Ask confirmation from the user.
# TODO: check with ZSH and BASH on the Linux (vps)
#
# @param {string} msg custom confirmation message (optional)
#                     default value is: 'Are you sure?'
#
# @example Default message
#
#   if ak.sh.confirm; then
#     echo 'The action confirmed!'
#   fi
#
# @example Custom message
#
#   if ak.sh.confirm 'Are you sure to delete .env file?'; then
#     rm -f .env
#   fi
#
# @example Without 'if' statement
#
#   ak.sh.confirm 'Are you sure to delete .env file?' && rm -f .env
#
function ak.sh.confirm() {
  local -r msg="${1:-Are you sure?} [y/N]: "
  local response

  # 'echo' used instead of '-p' flag for 'read' because of some shells doesn't support the '-p' flag
  # (in ZSH for example on Mac OS X systems)
  echo -n "${msg}"
  read -r response

  if [[ "${response}" =~ ^[yY][eE][sS]\|[yY]$ ]]; then
    true
  else
    false
  fi
}

#
# Search in the Shell history, highlighting matches, sorting results, limitate output
#
# @param {string}  *phrase phrase to search
# @param {integer}  limit  number of results to show (default is 50)
#                          (should be bigger 0)
#
function ak.sh.history() {
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
#   if ! ak.sh.commandExists node; then
#     echo 'NodeJS should be installed' >&2
#     exit 1s
#   fi
#
function ak.sh.commandExists() {
  local -r command="${1}";

  if [[ -x "$(command -v "${command}")" ]]; then
    return 0;
  fi

  return 1;
}

function ak.sh.showConfig() {
  cat "${AK_SCRIPT_PATH}/config.sh" | tail -n +3
}
