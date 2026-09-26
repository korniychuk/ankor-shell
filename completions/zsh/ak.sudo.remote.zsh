#!/usr/bin/env zsh

##
# Zsh completion for ak.sudo.remote-*: position 1 — ssh hosts as
# `alias → user@hostname` (same menu the operator's ssh completion shows),
# position 2 — minute presets (remote-lend only).
#
# ak.sudo.remote-lend-many: position 1 — minute presets AND hosts, positions
# ≥ 2 — hosts not typed yet. Space is the canonical separator; commas are
# accepted by the command, but nothing is completed after a comma.
#
# Naming: everything here is prefixed `_ak_` — NEVER take names from the zsh
# completion namespace (`_ssh_hosts`, `_hosts`, ...): a same-named function
# globally shadows the stock autoload one (see docs/tasks/00b, section 6).
##

# Fill the caller's `hosts` with `alias:description` entries, skipping the
# aliases given as arguments (dynamic scope — the caller declares `hosts`).
# @param $@ aliases to leave out
function _ak_sudo_remote_collect_hosts() {
  # Initializers are mandatory: a bare `local name` prints `name=value` when the
  # parameter exists in an enclosing scope (zsh without TYPESET_SILENT) — inside
  # a completion widget that noise corrupts the menu.
  local host='' description=''
  hosts=()
  while IFS=$'\t' read -r host description; do
    [[ -z "${host}" ]] && continue
    (( ${argv[(Ie)${host}]} )) && continue
    if [[ -n "${description}" ]]; then
      hosts+=("${host}:${description}")
    else
      hosts+=("${host}")
    fi
  done < <(ak.ssh.hosts.described 2> /dev/null)
}

# ak.sudo.remote-lend-many [minutes] <host>... / ak.sudo.remote-revoke-many <host>...
# @param $1 withMinutes  1 = offer the minute presets at position 2 (lend-many)
function _ak_sudo_remote_many() {
  local -r withMinutes="$1"
  local -a hosts=() typed=() presets=()
  local word=''
  # Words already typed (between the command and the current word); a
  # comma-joined word counts as several hosts.
  for word in "${(@)words[2,CURRENT-1]}"; do
    typed+=("${(@s:,:)word}")
  done
  _ak_sudo_remote_collect_hosts "${typed[@]}"

  if (( withMinutes && CURRENT == 2 )); then
    presets=('15:minutes' '30:minutes (default)' '60:minutes' '120:minutes')
    _describe -t minutes 'minutes' presets
  fi
  _describe -t hosts 'ssh host' hosts
}

function _ak_sudo_remote() {
  local -a hosts=()

  case "${words[1]}" in
    ak.sudo.remote-lend-many)   _ak_sudo_remote_many 1; return ;;
    ak.sudo.remote-revoke-many) _ak_sudo_remote_many 0; return ;;
  esac

  case "${CURRENT}" in
    2)
      _ak_sudo_remote_collect_hosts
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
  compdef _ak_sudo_remote ak.sudo.remote-lend ak.sudo.remote-revoke ak.sudo.remote-status \
    ak.sudo.remote-lend-many ak.sudo.remote-revoke-many
  # Same arrow separator the operator's ssh menu uses — scoped to our commands.
  zstyle ':completion:*:*:ak.sudo.remote-*:*' list-separator '→'
fi
