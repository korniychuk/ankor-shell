#!/usr/bin/env bash

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
