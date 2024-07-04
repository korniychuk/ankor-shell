#!/usr/bin/env bash

##
# Checks is an item is in an array
#
# @param {string} needle
# @param {array} haystack
#
##
function ak.array.inArray() {
  local needle="${1}"; shift
  local -a haystack=("$@")

  for item in "${haystack[@]}"; do
    if [[ "$item" == "$needle" ]]; then
      return 0; # found
    fi
  done

  return 1; # not found
}

# joinBy ,    a b c #a,b,c
# joinBy ' , '  a b c #a , b , c
# joinBy ')|('  a b c #a)|(b)|(c
# joinBy ' %s ' a b c #a %s b %s c
# joinBy $'\n'  a b c #a<newline>b<newline>c
# joinBy -    a b c #a-b-c
# joinBy '\'  a b c #a\b\c
function ak.array.joinBy {
  local d=$1;
  shift;

  echo -n "$1";
  shift;

  printf "%s" "${@/#/$d}";
}
