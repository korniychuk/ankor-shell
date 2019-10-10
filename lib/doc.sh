#!/usr/bin/env bash

#
# Some helpful function to print documentation
#

function ak.doc.headingLine() {
  local -r title="${1}"
  local -r char="${2:--}"
  local -ri length="${3:-80}"

  local -r strLen=${#title}
  local -r beforeLen=$(( (length - strLen - 2) / 2 ))
  local -r afterLen=$(( beforeLen + ( (length - strLen - 2) % 2 ? 1 : 0) ))

  echo "$(ak.str.repeat "${char}" "${beforeLen}") ${title} $(ak.str.repeat "${char}" "${afterLen}")"
}

function ak.doc.heading() {
  local -r title="${1}"
  local -r char="${2:--}"
  local -ri length="${3:-80}"

  ak.str.repeatn "${char}" "${length}"
  ak.doc.headingLine "${title}" "${char}" "${length}"
  ak.str.repeatn "${char}" "${length}"
}

#
# Like HTML's <hr> tag
#
function ak.doc.hr() {
  local -r char="${1:--}"

  ak.str.repeatn "${char}"
}
