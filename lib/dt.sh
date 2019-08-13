#!/usr/bin/env bash

#
# Date Time
#

### Variables ###
declare -i __akDtGlobal_isGNUDate=-1;

#function ak.dt.normalizeDate() {
#  echo ok
#}

#
# Check is GNU or Other(BSD for example) `date` util installed
#
# Example:
#
#   if ak.dt.isGNUDate; then
#     echo "You have GNU date installed"
#   elif ak.dt.isGNUDatePrefixed; then
#     echo "You have GNU date installed via `g` prefix"
#   else
#     echo "You don't have GNU Date installed"
#   fi
#
#
function ak.dt.isGNUDate() {
  if [[ ${__akDtGlobal_isGNUDate} -eq -1 ]]; then

    if date --version 2> /dev/null | grep GNU &> /dev/null; then
      __akDtGlobal_isGNUDate=0
    elif gdate --version 2> /dev/null | grep GNU &> /dev/null; then
      __akDtGlobal_isGNUDate=1
    else
      __akDtGlobal_isGNUDate=2
    fi
  fi

  return ${__akDtGlobal_isGNUDate}
}

#
# Check is GNU Date util version installed via prefix `g`
#
# Example:
#
#   if ak.dt.isGNUDatePrefixed; then
#     echo "You can use GNU Date with `g` prefix, like `gdate ...`"
#   fi
#
#
function ak.dt.isGNUDatePrefixed() {
  ak.dt.isGNUDate
  if [[ ${?} -eq 1 ]]; then
      return 0
  fi
  return 1
}
