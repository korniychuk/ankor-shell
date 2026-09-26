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

declare -r AK_SUDO_REMOTE_POLL_TIMEOUT_DEFAULT=15    # per-host overall poll deadline, seconds
declare -r AK_SUDO_REMOTE_POLL_CONNECT_TIMEOUT=5     # ssh ConnectTimeout of a poll, seconds
declare -r AK_SUDO_REMOTE_MANY_TIMEOUT_DEFAULT=45    # per-host lend/revoke deadline, s (daemon-reload can be slow)
declare -r __AK_SUDO_REMOTE_HOST_RE='^[A-Za-z0-9._@-]+$'

##
# Normalise the host words of a *-many command. Pure. Commas, spaces and tabs
# all separate; empties are dropped, duplicates removed (first occurrence
# wins). Refused: an all-digits word (a misplaced minutes argument), a leading
# '-' (an ssh option) and any character outside [A-Za-z0-9._@-] — hosts go to
# ssh after `--`, the check is still cheap.
# @param $1 cmd   command name for the error messages
# @param $2 hint  appended to the all-digits error (e.g. "minutes go FIRST…")
# @param $@ words
# @output one host per line (nothing when there is none)
# @returns 0 ok · 1 invalid host (message on stderr)
##
function __ak.sudo.remote.parseHosts() {
  local -r cmd="$1"
  local -r hint="$2"
  shift 2

  local seen=' ' host=''
  # shellcheck disable=SC2020  # a char-for-char map: comma, space, tab → newline
  while IFS= read -r host; do
    [[ -z "${host}" ]] && continue
    if [[ "${host}" =~ ^[0-9]+$ ]]; then
      ak.sh.err "${cmd}: '${host}' is not a host${hint}"
      return 1
    fi
    if [[ "${host}" == -* || ! "${host}" =~ ${__AK_SUDO_REMOTE_HOST_RE} ]]; then
      ak.sh.err "${cmd}: invalid host '${host}' — allowed: A-Z a-z 0-9 . _ @ - (not leading '-')."
      return 1
    fi
    [[ "${seen}" == *" ${host} "* ]] && continue
    seen+="${host} "
    printf '%s\n' "${host}"
  done < <(printf '%s\n' "$@" | tr ', \t' '\n\n\n')
}

# Run <remoteCmd> on every <host> in PARALLEL, without a tty or any prompt, and
# wait for all of them. Per host (1-based position i in the argument list):
#   <outDir>/<i>.out  remote stdout    <outDir>/<i>.err  ssh + remote stderr
#   <outDir>/<i>.rc   exit code (124 = timed out, 255 = ssh failed)
# The caller owns <outDir> and its cleanup (a subshell with EXIT/INT/TERM
# traps — the INT/TERM ones must `kill $(jobs -p)` before the EXIT rm).
#
# BatchMode fails fast instead of hanging the parallel poll on a passphrase
# prompt. ak.sh.timeout on top: ConnectTimeout covers ONLY the connect phase, a
# hung `bash -lic` after a successful connect needs its own deadline.
# @param $1 outDir          existing directory for the result files
# @param $2 timeoutSec      per-host overall deadline
# @param $3 acceptNewKeys   1 = StrictHostKeyChecking=accept-new (TOFU), 0 = strict
# @param $4 remoteCmd       ONE pre-composed, pre-validated command string
# @param $5.. hosts
function __ak.sudo.remote.pollAll() {
  local -r outDir="$1"
  local -r timeoutSec="$2"
  local -r acceptNewKeys="$3"
  local -r remoteCmd="$4"
  shift 4

  local -a sshOpts=(-T -n -o BatchMode=yes -o "ConnectTimeout=${AK_SUDO_REMOTE_POLL_CONNECT_TIMEOUT}")
  (( acceptNewKeys )) && sshOpts+=(-o StrictHostKeyChecking=accept-new)

  local -i i=0
  local host=''
  for host in "$@"; do
    i+=1
    (
      ak.sh.timeout "${timeoutSec}" ssh "${sshOpts[@]}" -- "${host}" "${remoteCmd}" \
        > "${outDir}/${i}.out" 2> "${outDir}/${i}.err"
      echo $? > "${outDir}/${i}.rc"
    ) 2> /dev/null &   # the job's own notices (e.g. "Killed") — ssh stderr is captured above
  done
  wait
}

##
# Poll ALL connectable hosts from ~/.ssh/config in PARALLEL and print each
# host's grant state: green granted / red no grant / gray no (or outdated)
# ankor-shell / yellow unreachable. Live state, no cache. A report, not a
# check — returns 0 even when some hosts are down; a summary line closes it.
#
# Porcelain parsing is tolerant by design: only `granted=` and
# `deadline_epoch=<digits>` are read, any other field (e.g. `lend_api=1`) is
# ignored, so a host may run a NEWER ankor-shell than this machine.
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

    # `command -v` probe: an explicit 127 beats guessing by stderr noise
    # (`bash -i` without a tty prints "no job control in this shell").
    local -r remoteCmd="bash -lic 'command -v ak.sudo.status > /dev/null || exit 127; ak.sudo.status --porcelain'"
    # accept-new (TOFU) stays as before: this poll sends nothing secret. Mind
    # that a key accepted here is trusted by a later lend-many as well.
    __ak.sudo.remote.pollAll "${tmpDir}" "${AK_SUDO_REMOTE_ALL_TIMEOUT:-${AK_SUDO_REMOTE_POLL_TIMEOUT_DEFAULT}}" \
      1 "${remoteCmd}" "${hosts[@]}"

    local -i i=0
    local host=''

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

# ── revoke-many / revoke-all ─────────────────────────────────────────────────

# Remote side of revoke-many: the porcelain line BEFORE the revoke (what there
# was), the revoke itself, the porcelain line AFTER it (the real state).
# `ak.sudo.revoke` never prompts: without a live grant it bails before sudo,
# with one the grant itself makes sudo passwordless.
# shellcheck disable=SC2016  # $? / $rc expand on the HOST, not here
declare -r __AK_SUDO_REMOTE_REVOKE_CMD="bash -lic 'command -v ak.sudo.revoke > /dev/null || exit 127; ak.sudo.status --porcelain; ak.sudo.revoke; rc=\$?; ak.sudo.status --porcelain; exit \$rc'"

##
# Classify one revoke result. Pure.
# @param $1 rc      ssh exit code
# @param $2 before  porcelain line before the revoke ('' when missing)
# @param $3 after   porcelain line after the revoke ('' when missing)
# @output revoked | none | still | unreachable | no_ak | timeout | failed
##
function __ak.sudo.remote.revokeState() {
  local -r rc="${1:-}"
  local -r before="${2:-}"
  local -r after="${3:-}"

  case "${rc}" in
    124) printf 'timeout\n'; return 0 ;;
    255) printf 'unreachable\n'; return 0 ;;
    127) printf 'no_ak\n'; return 0 ;;
  esac
  if [[ "${after}" == granted=1* ]]; then
    printf 'still\n'
    return 0
  fi
  if [[ "${rc}" != '0' || "${after}" != granted=0* ]]; then
    printf 'failed\n'
    return 0
  fi
  if [[ "${before}" == granted=1* ]]; then
    printf 'revoked\n'
    return 0
  fi
  printf 'none\n'
}

# Revoke on every <host> in parallel and print the summary in input order.
# Runs in a subshell that owns the temp dir and the traps.
# @param $1 lenient  1 = unreachable / not-installed hosts do not fail the exit
#                    code (a fleet report, like remote-status-all); 0 = they do
# @param $@ hosts
# @returns 0 · 1 (see the public commands)
function __ak.sudo.remote.revokeHosts() {
  local -r lenient="$1"
  shift
  local -a hosts=("$@")
  (
    local tmpDir=''
    tmpDir="$(mktemp -d "${TMPDIR:-/tmp}/ak-sudo-revoke-many.XXXXXX")" || exit 1
    trap 'rm -rf "${tmpDir}"' EXIT
    # Reap the jobs BEFORE the EXIT rm (see remote-status-all).
    trap 'kill $(jobs -p) 2> /dev/null; exit 130' INT
    trap 'kill $(jobs -p) 2> /dev/null; exit 143' TERM

    # Strict host keys: nothing secret travels, but a revoke is no place for a
    # first contact either.
    __ak.sudo.remote.pollAll "${tmpDir}" "${AK_SUDO_REMOTE_MANY_TIMEOUT:-${AK_SUDO_REMOTE_MANY_TIMEOUT_DEFAULT}}" \
      0 "${__AK_SUDO_REMOTE_REVOKE_CMD}" "${hosts[@]}"

    local -i width=0
    local host=''
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

    local -i i=0 nRevoked=0 nNone=0 nFailed=0 nUnreachable=0
    local rc='' out='' before='' after='' state='' dl='' clock='' mark='' color='' label='' details=''
    for host in "${hosts[@]}"; do
      i+=1
      rc="$(cat "${tmpDir}/${i}.rc" 2> /dev/null)"
      out="$(cat "${tmpDir}/${i}.out" 2> /dev/null)"
      before="$(printf '%s\n' "${out}" | grep -E '^granted=[01]' | head -n 1)"
      after="$(printf '%s\n' "${out}" | grep -E '^granted=[01]' | tail -n 1)"
      state="$(__ak.sudo.remote.revokeState "${rc}" "${before}" "${after}")"
      details=''

      case "${state}" in
        revoked)
          nRevoked+=1; mark='✔'; color="${cGreen}"; label='revoked'
          dl="${before##*deadline_epoch=}"
          dl="${dl%%[![:digit:]]*}"
          [[ -n "${dl}" ]] && clock="$(__ak.sudo.epochClock "${dl}")" && label+=" (was until ${clock})"
          ;;
        none)        nNone+=1; mark='·'; color="${cGray}"; label='no grant' ;;
        unreachable) nUnreachable+=1; mark='✘'; color="${cYellow}"; label="unreachable (ssh rc=${rc})" ;;
        timeout)     nFailed+=1; mark='✘'; color="${cRed}"; label="timed out — state UNKNOWN, check: ak.sudo.remote-status ${host}" ;;
        no_ak)       nUnreachable+=1; mark='✘'; color="${cGray}"; label='ankor-shell not installed' ;;
        still)       nFailed+=1; mark='✘'; color="${cRed}"; label='STILL GRANTED — revoke failed, check the host' ;;
        *)           nFailed+=1; mark='✘'; color="${cRed}"; label="failed (rc=${rc:-?})" ;;
      esac
      printf '%s%s %-*s  %s%s\n' "${color}" "${mark}" "${width}" "${host}" "${label}" "${cNC}"
      # Failures: the host's last significant output lines, indented.
      if [[ "${state}" != 'revoked' && "${state}" != 'none' ]]; then
        details="$(printf '%s\n%s\n' "${out}" "$(cat "${tmpDir}/${i}.err" 2> /dev/null)" \
          | grep -Ev 'no job control|cannot set terminal process group|^granted=|^[[:space:]]*$' \
          | tail -n 5 | sed 's/^/    /')"
        [[ -n "${details}" ]] && printf '%s\n' "${details}"
      fi
    done

    printf '\n%d revoked / %d no grant / %d unreachable / %d failed\n' \
      "${nRevoked}" "${nNone}" "${nUnreachable}" "${nFailed}"
    (( nFailed > 0 )) && exit 1
    (( nUnreachable > 0 && ! lenient )) && exit 1
    exit 0
  )
}

##
# Revoke the temporary sudo grant on SEVERAL hosts at once, in parallel, with
# a per-host summary in input order: ✔ revoked (was until …) · no grant ·
# ✘ unreachable / still granted / failed. Never prompts (no tty, BatchMode).
# @param $@ hosts — ~/.ssh/config aliases or user@host, space or comma separated
# @env AK_SUDO_REMOTE_MANY_TIMEOUT per-host deadline in seconds (default 45)
# @returns 0 every host handled (revoked or nothing to revoke) · 1 any host
#          unreachable / failed, or a usage error
#
# @example
#   ak.sudo.remote-revoke-many vps-alpha vps-bravo
#   ak.sudo.remote-revoke-many vps-alpha,vps-bravo,vps-charlie
##
function ak.sudo.remote-revoke-many() {
  local parsed=''
  parsed="$(__ak.sudo.remote.parseHosts 'ak.sudo.remote-revoke-many' '' "$@")" || return 1
  if [[ -z "${parsed}" ]]; then
    ak.sh.err 'Usage: ak.sudo.remote-revoke-many <host>...'
    return 1
  fi

  local -a hosts=()
  local host=''
  while IFS= read -r host; do hosts+=("${host}"); done <<< "${parsed}"
  __ak.sudo.remote.revokeHosts 0 "${hosts[@]}"
}

##
# Revoke the temporary sudo grant on EVERY connectable host of ~/.ssh/config
# (the same list as ak.sudo.remote-status-all), in parallel, with the summary
# of ak.sudo.remote-revoke-many. A fleet report: unreachable hosts and hosts
# without ankor-shell are listed, not counted as failures.
# @env AK_SUDO_REMOTE_MANY_TIMEOUT per-host deadline in seconds (default 45)
# @returns 0 · 1 a revoke FAILED on a reachable host (grant still there, or
#          state unknown after a timeout) — check that host
#
# @example
#   ak.sudo.remote-revoke-all
##
function ak.sudo.remote-revoke-all() {
  if (( $# > 0 )); then
    ak.sh.err "Usage: ak.sudo.remote-revoke-all  (no arguments)"
    return 1
  fi

  local -a hosts=()
  local host=''
  while IFS= read -r host; do
    [[ -n "${host}" ]] && hosts+=("${host}")
  done < <(ak.ssh.hosts)

  if (( ${#hosts[@]} == 0 )); then
    echo "ak.sudo.remote-revoke-all: no connectable hosts in ~/.ssh/config — nothing to revoke."
    return 0
  fi
  __ak.sudo.remote.revokeHosts 1 "${hosts[@]}"
}
