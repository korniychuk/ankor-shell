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
# Resolved GNU `date` binary name, cached across calls:
#   ""      - not resolved yet
#   "date"  - unprefixed `date` is GNU- or uutils-coreutils (Linux; uutils ships by
#             default on Ubuntu 25.10+/26.04) — GNU-CLI-compatible for our usage
#   "gdate" - unprefixed `date` is BSD (macOS), but the g-PREFIXED `gdate` is GNU (brew coreutils)
#   "-"     - no GNU-compatible date found at all
#
declare __akDtGlobal_dateBin="";

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
  __ak.dt.resolveDateBin
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
# Current timestamp it milliseconds
#
# Notes:
#   - always in UTC (no time zone)
#
function ak.dt.now.ms() {
  # %N - nano-seconds part of the current second
  echo -n $(( $(__ak.dt.gdate "+%s%N") / 1000000 ))
}

#
# Date in ISO 8601 format. Example: `2006-08-14T02:34:56-06:00`
#
function ak.dt.now.iso() {
  __ak.dt.gdate --iso-8601=seconds "${@}"
}

#
# Resolve (once, cached) which GNU `date` binary to use, following the rule:
#   prefer the UNPREFIXED GNU util -> else the g-PREFIXED variant -> else fail.
# Sets __akDtGlobal_dateBin; returns 0 if GNU date is available, 1 otherwise.
#
function __ak.dt.resolveDateBin() {
  if [[ -n "${__akDtGlobal_dateBin}" ]]; then
    [[ "${__akDtGlobal_dateBin}" != "-" ]]
    return ${?}
  fi

  # Accept GNU coreutils OR uutils-coreutils (the Rust reimpl. shipped by default on
  # Ubuntu 25.10+/26.04) — both are GNU-CLI-compatible for our usage and both print
  # their vendor in `--version`. BSD `date` (macOS) has no `--version`, so it is
  # excluded here and handled via the g-prefixed `gdate` branch below.
  if date --version 2> /dev/null | grep -qiE 'gnu|uutils'; then
    __akDtGlobal_dateBin="date"
  elif ak.sh.commandExists gdate && gdate --version 2> /dev/null | grep -qiE 'gnu|uutils'; then
    __akDtGlobal_dateBin="gdate"
  else
    __akDtGlobal_dateBin="-"
    return 1
  fi

  return 0
}

#
# Universal wrapper that runs the resolved GNU `date` (unprefixed `date` on Linux,
# `gdate` on macOS + coreutils). Errors if no GNU date is available.
#
# Example:
#
#     __ak.dt.gdate --utc "%H:%M"
#
function __ak.dt.gdate() {
  if ! __ak.dt.resolveDateBin; then
    ak.sh.err "No GNU-compatible date found — need GNU/uutils 'date' (Linux) or 'gdate' (macOS: brew install coreutils)"
    return 1
  fi

  "${__akDtGlobal_dateBin}" "${@}"
}
