#!/usr/bin/env bash

##
# Load shell-appropriate completion files from completions/<shell>/.
# Best-effort: a broken completion file must never break sourcing the library.
#
# Shell detection uses $ZSH_VERSION / $BASH_VERSION, NOT ak.sh.isZsh: the latter
# asks `ps` for the process name and returns 'unknown' whenever the shell was
# started with arguments (BSD ps prints the full command line, which then fails
# the anchored regex in ak.sh.type) — completions would silently never load.
# These variables are set by the running shell itself and cannot be wrong.
##
function __ak.completions.load() {
  # Initializers are mandatory: a bare `local name` prints `name=value` in zsh
  # when the parameter exists in an enclosing scope (no TYPESET_SILENT).
  local dir='' ext='' file=''

  if [[ -n "${ZSH_VERSION:-}" ]]; then
    dir="${AK_SCRIPT_PATH}/completions/zsh"
    ext='zsh'
    # Function-scoped (localoptions): a non-matching glob is a FATAL error in
    # zsh, and the setting must not leak into the user's shell.
    setopt localoptions nullglob
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    dir="${AK_SCRIPT_PATH}/completions/bash"
    ext='bash'
    # No `shopt -s nullglob` here: it is GLOBAL in bash and would silently
    # change globbing in the user's interactive shell. Bash leaves an
    # unmatched pattern literal, and the `-f` guard below drops it.
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
