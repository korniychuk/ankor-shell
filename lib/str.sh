#!/usr/bin/env bash

#
# Library to work with strings
#

#
# Repeat a string N times
# @param {string}  str   a string
# @param {integer} times how many times to repeat
# @returns {string} repeated string
#
# @example
#
#  ak.str.repeat "-" # repeats "-" 80 times
#  ak.str.repeat "-->" 3 # repeats "-->" 3 times. Result "-->-->-->"
#
function ak.str.repeat() {
  local -r str="${1}"
  local -ri times="${2:-80}"

  if [[ ${times} -gt 0 ]]; then
    printf -- "${str}"'%.s' $(eval "echo {1..${times}}");
  fi
}

#
# See {@link ak.str.repeat}
#
function ak.str.repeatn() {
  ak.str.repeat "${@}"
  echo;
}
