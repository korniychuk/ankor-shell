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

