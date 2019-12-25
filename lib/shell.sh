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
# @example:
#
#   if [[ "$(ak.sh.type)" == 'zsh' ]]; then
#     echo "I'm ZSH!"
#   fi
#
function ak.sh.type() {
  if [[ ! -z "${ZSH_VERSION+x}" ]];                                   then echo 'zsh';
  elif [[ ! -z "${BASH_VERSION+x}" ]];                                then echo 'bash';
  else                                                                     echo 'unknown';
  fi
}

#
# @example:
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
