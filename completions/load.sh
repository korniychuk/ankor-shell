#!/usr/bin/env bash

##
# Load shell-appropriate completion files from completions/<shell>/.
# Best-effort: a broken completion file must never break sourcing the library.
##
function __ak.completions.load() {
  local dir ext file

  if ak.sh.isZsh; then
    dir="${AK_SCRIPT_PATH}/completions/zsh"
    ext='zsh'
    setopt localoptions nullglob
  elif ak.sh.isBash; then
    dir="${AK_SCRIPT_PATH}/completions/bash"
    ext='bash'
  else
    return 0
  fi

  [[ -d "${dir}" ]] || return 0

  for file in "${dir}"/*."${ext}"; do
    [[ -f "${file}" ]] || continue
    source "${file}" || ak.sh.warn "failed to load completion '${file}' — skipped."
  done
  return 0
}

__ak.completions.load
