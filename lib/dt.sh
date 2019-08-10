#!/usr/bin/env bash

#
# Library: Date Time
#

#
### Variables ###
#

declare -r AK_DT_FORMAT_DATE="%Y-%m-%d"
declare -r AK_DT_FORMAT_TIME="%H:%M:%S"

declare -i __akDtGlobal_isGNUDate=-1;

#
### Functions ###
#

function ak.dt.normalizeDate() {
  local -r dateStr="${1//[.\/\\-]/-}"

  if ak.dt.isDateValid "${dateStr}"; then
      echo "Invalid date" >&2
      return 1
  fi

}

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

#
# Validate date format and return 0 / 1
#
# Example:
#
#   if ak.dt.isDateValid "2019-08-23"; then
#     echo "The date is valid"
#   fi
#
# Notes:
#   - Works with BSD(Mac OS) and GNU(Linux) date utils
#
# Helpful links:
#   - https://stackoverflow.com/questions/21221562/bash-validate-date/26972354
#   - https://stackoverflow.com/questions/18731346/validate-date-format-in-a-shell-script
#
function ak.dt.isDateValid() {
  local -r dateStr="${1}"

  if [[ -z "${dateStr}" ]]; then
      return 1
  fi

  if ak.dt.isGNUDate; then
      date "+${AK_DT_FORMAT_DATE}" -d "${dateStr}" &>/dev/null
  elif ak.dt.isGNUDatePrefixed; then
      gdate "+${AK_DT_FORMAT_DATE}" -d "${dateStr}" &>/dev/null
  else
      date -f "${AK_DT_FORMAT_DATE}" -j "${dateStr}" &>/dev/null
  fi

  return $?
}

function ak.dt.getCurrentDate() {
  date "+${AK_DT_FORMAT_DATE}"
}

function ak.dt.getCurrentTime() {
  date "+${AK_DT_FORMAT_TIME}"
}

function ak.dt.getCurrentDateTime() {
  echo "$(ak.dt.getCurrentDate) $(ak.dt.getCurrentTime)"
}
