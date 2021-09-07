#!/usr/bin/env bash

#
# Library to work with strings
# TODO: ak.str.trim
#       ak.str.trimLeft
#       ak.str.trimRight
#       ak.str.padLeft - https://unix.stackexchange.com/questions/398819/padding-trailing-whitespaces-in-a-string-with-another-character
#       ak.str.padRight
#

##
# @param {String}  [msg]
# @param {String}  [char=-]
# @param {Integer} [width=80]
#
# @stdout {String} Centrated `msg` padded by `char` to rich `width`
#
# @example:
#
#   > ak.str.header 'Hello, world!'
#   # --------------------------------- Hello, world! --------------------------------
#
##
function ak.str.header() {
  local -r msg="$1"
  local -r char="${2:--}"
  local -r -i width=${3:-80}

  local -r -i msgLen=$(( ${#msg} + 2 ))
  local -r -i lineLen=$(( (width - msgLen) / 2 ))
  local -r lineAfter="$(printf -- "${char}%.0s" $(eval "echo {1..$lineLen}"))"
  local -r lineBefore="$lineAfter$([[ $(((width - msgLen) % 2 )) -ge 1 ]] && echo "$char")"

  echo  "$lineBefore $msg $lineAfter"
}

##
# See {@link ak.str.repeat} + adds a linebreak
##
function ak.str.headern() {
  ak.str.header "$@"
  echo
}

##
# Repeat a string N times

# @param {string}  str   a string
# @param {integer} times how many times to repeat
#
# @output {string} repeated string
# @see https://stackoverflow.com/a/5349842/4843221
# @see https://github.com/koalaman/shellcheck/wiki/SC2051#rationale
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
    printf -- "${str}"'%.s' $(eval "echo {1..${times}}")
  fi
}

##
# See {@link ak.str.repeat} + adds a linebreak
##
function ak.str.repeatn() {
  ak.str.repeat "${@}"
  echo
}

##
# Replaces sub-string in a string using Perl RegExr replacement pattern.
#
# @output {string} String with replaced sub-string
# TODO: test it
#
##
function ak.str.replace() {
  local _str; read -r _str; [[ -z "${_str}" ]] && _str="$1" && shift
  local -r _regExpReplacer="${1}"

  echo -n "$_str" | perl -0777 -pe "${_regExpReplacer}"
}

##
# @example 'he_llo ME wor-ld 23' -> 'HeLloMEWorLd23'
##
function ak.str.toTitleCase() {
  echo -n "$1" | perl -pe 's/(^|[_\s-])(\w)/\U$2/g'
}

##
# @example 'he_llo ME wor-ld 23' -> 'heLloMEWorLd23'
##
function ak.str.toCamelCase() {
  echo -n "$1" | perl -pe 's/([_\s-])(\w)/\U$2/g'
}

##
# @example 'he_llo ME wor-ld 23' -> 'he-llo-me-wor-ld-23'
##
function ak.str.toKebabCase() {
  ak.str.toLowerCase "$1" | perl -pe 's/([_\s-])(\w)/-$2/g'
}

##
# @example 'he_llo ME wor-ld 23' -> 'he_llo me wor-ld 23'
# @see the source https://stackoverflow.com/a/2264537/4843221
##
function ak.str.toLowerCase() {
  echo -n "$1" | tr '[:upper:]' '[:lower:]'
}

##
# @example 'he_llo ME wor-ld 23' -> 'HE_LLO ME WOR-LD 23'
# @see {@link ak.str.toLowerCase}
##
function ak.str.toUpperCase() {
  echo -n "$1" | tr '[:lower:]' '[:upper:]'
}

##
# Deletes final '\n' char if it exists
# @see https://stackoverflow.com/questions/1654021
# TODO: find better way & use universal ak.str.trimRight '\n'
##
function ak.str.trimFinalNewLine() {
  perl -pe 'chomp if eof'
}
