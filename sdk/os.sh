#!/usr/bin/env bash

#
# @example:
#
#   if [[ "$(ak.os.type)" == "MacOS" ]]; then
#     echo "I'am Mac OS X!"
#   fi
#
# Helpful links:
#   - https://stackoverflow.com/questions/394230/how-to-detect-the-os-from-a-bash-script
#
function ak.os.type() {
  case "$OSTYPE" in
    bsd*)     echo "BSD" ;;
    darwin*)  echo "MacOS" ;;
    linux*)   echo "Linux" ;;
    msys*)    echo "Windows" ;;
    solaris*) echo "Solaris" ;;
    *)        echo "unknown: $OSTYPE" ;;
  esac
}

function ak.os.type.isBSD() {
  test "$(ak.os.type)" "==" "BSD"
  return $?
}

#
# @example:
#
#   if ak.os.type.isMacOS; then
#     echo "I'am Mac OS X!"
#   fi
#
function ak.os.type.isMacOS() {
  test "$(ak.os.type)" "==" "MacOS"
  return $?
}

function ak.os.type.isLinux() {
  test "$(ak.os.type)" "==" "Linux"
  return $?
}

function ak.os.type.isWindows() {
  test "$(ak.os.type)" "==" "Windows"
  return $?
}

function ak.os.type.isSolaris() {
  test "$(ak.os.type)" "==" "Solaris"
  return $?
}
