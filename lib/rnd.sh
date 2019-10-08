#!/usr/bin/env bash

##
# Generate any random things here
# @module: Random
##

##
# Generate Mongo DB's Object ID for now
#
# @output {string} Generated ObjectID
#
# @example:
#
#   ak.rnd.objectId   # 5e272bec8a1fed605aa7369f
#
##
function ak.rnd.objectId() {
  printf "%x" $(date "+%s")
  local -i i=0
  for (( i = 0; i < 16; ++i )); do
      printf "%x" $(( RANDOM % 16 ))
  done
  echo
}

##
# Generate random integer in specified range
#
# @param {integer} from The mininum number (inclusive)
# @param {integer} to   The maximum number (inclusive)
#
# @output {integer} Generated number
#
# @example:
#
#   ak.rnd.int 1 10   # 7
#
# Notice: $RANDOM is a bad way because of in the next case will always return the same value
#
#   echo "$(echo $RANDOM)" # always the same
#
##
function ak.rnd.int() {
  local -r -i from="${1}"
  local -r -i to="${2}"

  shuf -i "${from}-${to}" -n 1
}

##
# Generate random second
#
# @param {'*'} [type='*'] '*' means default range. From 0 to 59, both inclusive.
#
# @output {integer} Generated second from 0 to 59
#
# @example:
#
#   ak.rnd.second      # 23 - a random second
#   ak.rnd.second '*'  # 53 - the same
#
##
##
# Generate random second in range
#
# @param {integer} from Mininum second (>= 0 && <= to) (inclusive)
# @param {integer} to   Maximum second (<= 59)         (inclusive)
#
# @output {integer} Generated second from 0 to 59
#
# @example:
#
#   ak.rnd.second 0  5   # 4  - a random second in [0, 5] range
#   ak.rnd.second 30 45  # 38 - the same for [30, 45] range
#
##
##
# Get current second of the system clock
#
# @param {'~'} type '~' means current second
#
# @output {integer} Current second
#
# @example:
#
#   ak.rnd.second '~'  # 18
#
# TODO: implement __ak.rnd.time-item MIN MAX from|type to?
#       for generating any kind of time item (minutes/seconds/hours)
#       and implement ak.rnd.hour likewise
##
function ak.rnd.second() {
  local -r -i MIN=0
  local -r -i MAX=59
  local -i from=${MIN}
  local -i to=${MAX}

  if (($# == 1)); then
    if [[ "${1}" == "~" ]]; then
      __ak.dt.gdate '+%S'
      return 0
    elif [[ "${1}" != "*" ]]; then
      echo 'ERROR! Invalid argument' >&2
      return 1
    fi
  elif (($# == 2)); then
    from="${1}"
    to="${2}"

    if ((from < MIN)); then
      echo "ERROR! 'from' should not be less than ${MIN}" >&2
      return 3
    fi
    if ((to > MAX)); then
      echo "ERROR! 'to' should not be bigger than ${MAX}" >&2
      return 4
    fi
    if ((from > to)); then
      echo "ERROR! 'from' can't be bigger than 'to'" >&2
      return 5
    fi
  elif (($# != 0)); then
    echo 'ERROR! Invalid arguments number' >&2
    return 2
  fi

  ak.rnd.int "${from}" "${to}"
  return 0
}

##
# Generate random minute or get current one
#
# @see {@link ak.rnd.second} for details
##
ak.rnd.minute() {
  if (($# == 1)) && [[ "${1}" == "~" ]]; then
    __ak.dt.gdate '+%M'
    return 0
  fi

  ak.rnd.second "${@}"
  return $?
}
