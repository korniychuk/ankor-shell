#!/usr/bin/env bash

#
# Library: Generator
#

#
# Generate Mongo DB's Object ID for now
#
function ak.gen.objectId() {
  printf "%x" $(date "+%s")
  local -i i=0
  for (( i = 0; i < 16; ++i )); do
      printf "%x" $(( RANDOM % 16 ))
  done
  echo
}
