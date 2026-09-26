#!/usr/bin/env bash

##
# ak.sudo.remote-* — run the ak.sudo.* commands of features/sudo.sh on another
# host over SSH. Sourced right after features/sudo.sh, whose helpers it reuses
# (__ak.sudo.validMinutes, __ak.sudo.formatRemaining).
##

# ── remote control (ak.sudo.* on another host over SSH) ──────────────────────

# Run `<remoteFn> [arg]` on <host> through the remote interactive login shell
# (ankor-shell must be loaded in the remote rc). The command is composed
# LOCALLY into ONE argv element, so the remote shell re-parses exactly what we
# built — the collapsed-quoting trap from the file header cannot happen by
# construction. `arg` must be pre-validated by the caller: nothing
# shell-escapable may reach this point.
# @param $1 remoteFn remote function to call (e.g. ak.sudo.lend)
# @param $2 host     ssh destination (config alias or user@host)
# @param $3 arg      optional single pre-validated argument
function __ak.sudo.remote.exec() {
  local -r remoteFn="$1"
  local -r host="$2"
  local -r arg="${3:-}"

  local cmd="${remoteFn}"
  [[ -n "${arg}" ]] && cmd="${cmd} ${arg}"

  # -t: the remote sudo password prompt needs a tty;
  # --: a host starting with '-' cannot be mistaken for an ssh option.
  ssh -t -o ConnectTimeout="${AK_SUDO_REMOTE_TIMEOUT:-10}" -- "${host}" "bash -lic '${cmd}'"
  local -r rc=$?

  if (( rc == 255 )); then
    ak.sh.err "ssh could not connect to '${host}' (rc=255)."
    return 255
  fi
  if (( rc == 127 )); then
    ak.sh.err "'${remoteFn}' not found on '${host}' — ankor-shell is not loaded in its interactive rc."
    return 127
  fi
  return ${rc}
}

##
# Lend passwordless sudo on a REMOTE host (ak.sudo.lend over SSH).
# Minutes are validated LOCALLY (same 1..1440 rule) before anything is sent.
# Omitted minutes are NOT defaulted here — the remote side owns the default
# (single source of truth).
#
# @param $1 host    ssh destination — ~/.ssh/config alias or user@host
# @param $2 minutes (optional) grant duration, 1..1440
# @env AK_SUDO_REMOTE_TIMEOUT ssh ConnectTimeout in seconds (default 10)
#
# @example
#   ak.sudo.remote-lend vps-india 20
#   ak.sudo.remote-lend vps-golf    # remote default (30m) applies
##
function ak.sudo.remote-lend() {
  local -r host="${1:-}"
  local -r mins="${2:-}"

  if [[ -z "${host}" ]] || (( $# > 2 )); then
    ak.sh.err "Usage: ak.sudo.remote-lend <host> [minutes 1..1440]"
    return 1
  fi
  if [[ -n "${mins}" ]] && ! __ak.sudo.validMinutes "${mins}"; then
    ak.sh.err "ak.sudo.remote-lend: invalid minutes '${mins}' — expected an integer 1..1440."
    return 1
  fi

  __ak.sudo.remote.exec 'ak.sudo.lend' "${host}" "${mins}"
}

##
# Revoke the temporary passwordless sudo on a REMOTE host (ak.sudo.revoke over SSH).
#
# @param $1 host ssh destination — ~/.ssh/config alias or user@host
# @env AK_SUDO_REMOTE_TIMEOUT ssh ConnectTimeout in seconds (default 10)
#
# @example
#   ak.sudo.remote-revoke vps-india
##
function ak.sudo.remote-revoke() {
  local -r host="${1:-}"

  if [[ -z "${host}" ]] || (( $# > 1 )); then
    ak.sh.err "Usage: ak.sudo.remote-revoke <host>"
    return 1
  fi

  __ak.sudo.remote.exec 'ak.sudo.revoke' "${host}"
}

##
# Report the temporary-sudo grant state of a REMOTE host (ak.sudo.status over SSH).
#
# @param $1 host ssh destination — ~/.ssh/config alias or user@host
# @env AK_SUDO_REMOTE_TIMEOUT ssh ConnectTimeout in seconds (default 10)
#
# @example
#   ak.sudo.remote-status vps-bravo
##
function ak.sudo.remote-status() {
  local -r host="${1:-}"

  if [[ -z "${host}" ]] || (( $# > 1 )); then
    ak.sh.err "Usage: ak.sudo.remote-status <host>"
    return 1
  fi

  __ak.sudo.remote.exec 'ak.sudo.status' "${host}"
}

##
# Poll ALL connectable hosts from ~/.ssh/config in PARALLEL and print each
# host's grant state: green granted / red no grant / gray no (or outdated)
# ankor-shell / yellow unreachable. Live state, no cache. A report, not a
# check — returns 0 even when some hosts are down; a summary line closes it.
#
# @env AK_SUDO_REMOTE_ALL_TIMEOUT per-host overall timeout in seconds (default 15)
#
# @example
#   ak.sudo.remote-status-all
##
function ak.sudo.remote-status-all() {
  if (( $# > 0 )); then
    ak.sh.err "Usage: ak.sudo.remote-status-all  (no arguments)"
    return 1
  fi

  # Every `local` here carries an initializer on purpose: zsh without
  # TYPESET_SILENT PRINTS `name=value` for a bare `local name` when the
  # parameter already exists in an enclosing scope (that leaked a stray
  # `host=''` line into this report).
  local -a hosts=()
  local host=''
  while IFS= read -r host; do
    [[ -n "${host}" ]] && hosts+=("${host}")
  done < <(ak.ssh.hosts)

  if (( ${#hosts[@]} == 0 )); then
    echo "ak.sudo.remote-status-all: no connectable hosts in ~/.ssh/config — nothing to poll."
    return 0
  fi

  # Whole body in a subshell: the EXIT trap reliably removes the temp dir on
  # ALL exit paths (incl. Ctrl-C mid-poll), and background jobs stay silent in
  # interactive shells.
  (
    local tmpDir=''
    tmpDir="$(mktemp -d "${TMPDIR:-/tmp}/ak-sudo-status-all.XXXXXX")" || exit 1
    trap 'rm -rf "${tmpDir}"' EXIT
    # Reap the per-host jobs BEFORE the EXIT rm: a surviving job re-creating
    # its .rc file mid-removal would leave the temp dir behind (ENOTEMPTY).
    trap 'kill $(jobs -p) 2> /dev/null; exit 130' INT
    trap 'kill $(jobs -p) 2> /dev/null; exit 143' TERM

    # No tty, no prompts: BatchMode fails fast instead of hanging the parallel
    # poll on a passphrase prompt (the remote side only ever calls `sudo -n`).
    # `command -v` probe: an explicit 127 beats guessing by stderr noise
    # (`bash -i` without a tty prints "no job control in this shell").
    # ak.sh.timeout on top: ConnectTimeout covers ONLY the connect phase, a
    # hung `bash -lic` after a successful connect needs its own deadline.
    local -r remoteCmd="bash -lic 'command -v ak.sudo.status > /dev/null || exit 127; ak.sudo.status --porcelain'"
    local -i i=0
    local host=''
    for host in "${hosts[@]}"; do
      i+=1
      (
        ak.sh.timeout "${AK_SUDO_REMOTE_ALL_TIMEOUT:-15}" \
          ssh -T -n -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
            -- "${host}" "${remoteCmd}" > "${tmpDir}/${i}.out" 2> /dev/null
        echo $? > "${tmpDir}/${i}.rc"
      ) &
    done
    wait

    # hosts come from ak.ssh.hosts already sorted → stable alphabetical output
    # regardless of response order.
    local -i width=0
    for host in "${hosts[@]}"; do
      (( ${#host} > width )) && width=${#host}
    done

    local cGreen='' cRed='' cYellow='' cGray='' cNC=''
    if [[ -t 1 ]]; then
      cGreen="${AK_COLOR_Green}"
      cRed="${AK_COLOR_Red}"
      cYellow="${AK_COLOR_Yellow}"
      cGray="${AK_COLOR_Gray}"
      cNC="${AK_COLOR_NC}"
    fi

    local -i nGranted=0 nNoGrant=0 nUnreachable=0 nNoAk=0
    local rc='' out='' line='' color='' label='' dl='' left=''
    i=0
    for host in "${hosts[@]}"; do
      i+=1
      rc="$(cat "${tmpDir}/${i}.rc" 2> /dev/null)"
      out="$(cat "${tmpDir}/${i}.out" 2> /dev/null)"
      # A login shell may echo motd/rc noise around the payload — grep the line.
      line="$(printf '%s\n' "${out}" | grep -E '^granted=[01]' | head -n 1)"

      if [[ "${rc}" == '124' || "${rc}" == '255' ]]; then
        color="${cYellow}"; label='unreachable (timeout)'; nUnreachable+=1
      elif [[ "${rc}" == '127' ]]; then
        color="${cGray}"; label='ankor-shell not installed'; nNoAk+=1
      elif [[ "${line}" == granted=1* ]]; then
        color="${cGreen}"; label='granted'; nGranted+=1
        # The remote sent an EPOCH, so the countdown and the wall-clock time are
        # rendered here — in the operator's timezone, not the host's.
        dl="${line##*deadline_epoch=}"
        dl="${dl%%[![:digit:]]*}"
        left="$(__ak.sudo.formatRemaining "${dl}")"
        [[ -n "${left}" ]] && label="granted — ${left}"
      elif [[ "${line}" == granted=0* ]]; then
        color="${cRed}"; label='no grant'; nNoGrant+=1
      else
        # Reachable, ak.sudo.status exists, but no porcelain line: an old
        # ankor-shell that predates --porcelain — do NOT lie with "no grant".
        color="${cGray}"; label='ankor-shell outdated'; nNoAk+=1
      fi

      printf '%s%-*s  %s%s\n' "${color}" "${width}" "${host}" "${label}" "${cNC}"
    done

    printf '\n%d granted / %d no grant / %d unreachable / %d without ankor-shell\n' \
      "${nGranted}" "${nNoGrant}" "${nUnreachable}" "${nNoAk}"
  )
  return 0
}
