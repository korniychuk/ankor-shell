#!/usr/bin/env bash

function ak.core.update() {
  cd "${AK_SCRIPT_PATH}"

  if ak.git.isClean; then
      git pull
  else
      git stash && git pull && git stash pop
  fi
}
