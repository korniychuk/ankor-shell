#!/usr/bin/env bash

#
# Library: Date Time
# TODO: Check GNU Date installed
#

#
### Variables ######################################################################################
#

declare -r AK_DT_FORMAT_DATE="%Y-%m-%d"
declare -r AK_DT_FORMAT_TIME="%H:%M:%S"

#
# -1 - not checked
#  0 - not GNU Date. May be BSD version from the Mac OS X
#  1 - default `date` is GNU Date
#  2 - default `date` it not GNU, however GNU version is available under `gdate` alias
#
declare -i __akDtGlobal_dateVendor=-1;

#
### Functions ######################################################################################
#


# TODO: Finish
#function ak.dt.normalizeDate() {
#  local -r dateStr="${1//[.\/\\-]/-}"
#
#  if ak.dt.isDateValid "${dateStr}"; then
#      echo "Invalid date" >&2
#      return 1
#  fi
#
#}

#
# Check is GNU Date util version installed via prefix `g`
#
# Example:
#
#   if ak.dt.hasGNUDate; then
#     echo "You can use GNU Date via the `__ak.dt.gdate` wrapper"
#     __ak.dt.gdate --utc "%H:%M"
#   fi
#
#
function ak.dt.hasGNUDate() {
  __ak.dt.checkDateVendor
  if [[ ${?} -eq 1 ]] || [[ ${?} -eq 2 ]]; then
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

  __ak.dt.gdate "+${AK_DT_FORMAT_DATE}" -d "${dateStr}" &>/dev/null

  return $?
}

#
# Print current date and time in the sortable format
#
# Examples:
#
#   ak.dt.now         # 2019-09-14 13:13:59 (GMT+3)
#   ak.dt.now --utc   # 2019-09-14 10:13:59 (UTC)
#
# Notes:
#   - "--utc" flag can be used with all ak.dt.now.* functions
#   - you can pass any arguments of GNU Date utility. "--utc" is one of them.
#
function ak.dt.now() {
  echo "$(ak.dt.now.date "${@}") $(ak.dt.now.time "${@}")"
}

function ak.dt.now.date() {
  __ak.dt.gdate "+${AK_DT_FORMAT_DATE}" "${@}"
}

function ak.dt.now.time() {
  __ak.dt.gdate "+${AK_DT_FORMAT_TIME}" "${@}"
}

#
# Current timestamp
#
# Notes:
#   - always in UTC (no time zone)
#
function ak.dt.now.timestamp() {
  __ak.dt.gdate "+%s" "${@}"
}

#
# Date in ISO 8601 format. Example: `2006-08-14T02:34:56-06:00`
#
function ak.dt.now.iso() {
  __ak.dt.gdate --iso-8601=seconds "${@}"
}

#
# Check is GNU or Other(BSD for example) `date` util installed
#
function __ak.dt.checkDateVendor() {
  if [[ ${__akDtGlobal_dateVendor} -eq -1 ]]; then

    if date --version 2> /dev/null | grep GNU &> /dev/null; then
      __akDtGlobal_dateVendor=1
    elif gdate --version 2> /dev/null | grep GNU &> /dev/null; then
      __akDtGlobal_dateVendor=2
    else
      __akDtGlobal_dateVendor=0
    fi
  fi

  return ${__akDtGlobal_dateVendor}
}

#
# Universal wrapper to use `date` or `gdate` if the first one is not available.
#
# Example:
#
#     __ak.dt.gdate --utc "%H:%M"
#
function __ak.dt.gdate() {
  __ak.dt.checkDateVendor
  if [[ ${?} -eq 1 ]]; then
      date "${@}"
  elif [[ ${?} -eq 2 ]]; then
      gdate "${@}"
  else
      echo "ERROR! Can't find GNU Date utility"
  fi

  return ${?}
}
