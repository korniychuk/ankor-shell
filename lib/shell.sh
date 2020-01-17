#!/usr/bin/env bash

#
# TODO: Implement normalize boolean function '', 0, false, null
#   - https://unix.stackexchange.com/questions/185670/what-is-a-best-practice-to-represent-a-boolean-value-in-a-shell-script
#   - https://www.google.com/search?q=bash+falsy+values&oq=bash+falsy+values&aqs=chrome..69i57j0.4094j0j4&sourceid=chrome&ie=UTF-8
#

#
# Shell independent command.
# This commands should works in any shell.
#
# Notice: 'SH' the function names means a shortcut of 'Shell'. It doesn't mean this commands for legasy shell - 'SH'
#

#
# Returns currently opened SHELL type.
# Notice: This library works only with bash & zsh
#
# @example
#
#   if [[ "$(ak.sh.type)" == 'zsh' ]]; then
#     echo "I'm ZSH!"
#   fi
#
function ak.sh.type() {
  local type
  type=$(ps -hp $$ | grep sh | sed -E 's/.*((z|ba|c|tc|k)sh)$/\1/g')

  case "$type" in
    zsh)    echo 'zsh'       ;;
    bash)   echo 'bash'      ;;
    *)      echo 'unknown'   ;;
  esac
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
# @param {string}  *phrase          phrase to search
# @param {integer}  limit           number of results to show (default is 50)
#                                   (should be bigger 0)
# @param {boolean}  isCaseSensitive true/false or 0/1 (default is false)
#
# TODO: Use boolean convertion function for type casting
#
function ak.sh.history() {
  local -r phrase="${1}"
  local -r limit="${2:-50}"
  local -r isCaseSensitive=${3:-false}

  if [[ -z "${phrase}" ]]; then
      echo 'ArgError: No search phrase' >&2
      return 1
  fi

  if [[ "${limit}" -le 0 ]]; then
      echo 'ArgError: limit should greater then 0' >&2
      return 2
  fi

  local grepParams=()
  if [[ "${isCaseSensitive}" != "true" ]] && [[ "${isCaseSensitive}" != "1" ]]; then
      grepParams+='-i'
  fi

  # Notice: 'awk' used for trimming leading and trailing space.
  # See: https://unix.stackexchange.com/questions/102008/how-do-i-trim-leading-and-trailing-whitespace-from-each-line-of-some-output/205854
  history \
    | grep "${grepParams[@]}" "${phrase}" \
    | awk '{$1=$1};1' \
    | sort -r -k2 -u \
    | sort -k1 \
    | tail -n ${limit} \
    | grep "${grepParams[@]}" --color=auto "${phrase}"
}

#
# @example
#
#   if ! ak.sh.commandExists node; then
#     echo 'NodeJS should be installed' >&2
#     exit 1s
#   fi
#
function ak.sh.commandExists() {
  local -r command="${1}";

  if [[ ! -x "$(command -v "${command}")" ]]; then
    false
  fi
}

function ak.sh.showConfig() {
  cat "${AK_SCRIPT_PATH}/config.sh" | tail -n +3
}
