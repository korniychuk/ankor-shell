#!/usr/bin/env zsh

##
# Zsh completion for ak.sudo.remote-*: position 1 — ssh hosts as
# `alias → user@hostname` (same menu the operator's ssh completion shows),
# position 2 — minute presets (remote-lend only).
#
# Naming: everything here is prefixed `_ak_` — NEVER take names from the zsh
# completion namespace (`_ssh_hosts`, `_hosts`, ...): a same-named function
# globally shadows the stock autoload one (see docs/tasks/00b, section 6).
##

function _ak_sudo_remote() {
  # Initializers are mandatory: a bare `local name` prints `name=value` when the
  # parameter exists in an enclosing scope (zsh without TYPESET_SILENT) — inside
  # a completion widget that noise corrupts the menu.
  local -a hosts=()
  local host='' description=''

  case "${CURRENT}" in
    2)
      hosts=()
      while IFS=$'\t' read -r host description; do
        [[ -z "${host}" ]] && continue
        if [[ -n "${description}" ]]; then
          hosts+=("${host}:${description}")
        else
          hosts+=("${host}")
        fi
      done < <(ak.ssh.hosts.described 2> /dev/null)
      _describe -t hosts 'ssh host' hosts
      ;;
    3)
      [[ "${words[1]}" == 'ak.sudo.remote-lend' ]] && _values 'minutes' 15 30 60 120
      ;;
  esac
}

# compdef, NOT fpath+autoload: compinit usually already ran by the time this
# library is sourced from the rc — extending fpath would be too late. The guard
# keeps configs without compinit working.
if (( $+functions[compdef] )); then
  compdef _ak_sudo_remote ak.sudo.remote-lend ak.sudo.remote-revoke ak.sudo.remote-status
  # Same arrow separator the operator's ssh menu uses — scoped to our commands.
  zstyle ':completion:*:*:ak.sudo.remote-*:*' list-separator '→'
fi
