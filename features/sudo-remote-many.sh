#!/usr/bin/env bash

##
# ak.sudo.remote-lend-many — ONE sudo password, a lend on MANY hosts, and a
# per-host summary. Sourced after features/sudo-remote.sh: reuses
# __ak.sudo.remote.pollAll, __ak.sudo.validMinutes and the AK_SUDO_* constants.
# Design, threat model and pitfalls: docs/tasks/00f-sudo-remote-lend-many.md.
#
# Layout:
# - pure helpers (parseArgs, probeState, classify, formatClock, formatDeadline,
#   reason, successNote, formatDetails) take everything as parameters and run
#   without any host — that is how they are tested;
# - orchestration helpers (probe, askPassword, launch, await, record,
#   lendRound, printSuccess, printSummary) share the run state that
#   __ak.sudo.many.run declares, through dynamic scope: tmpDir, mins, width,
#   whenWidth, timeoutSec, connectSec, lendCmd, the colours, and the per-host
#   associative arrays hostState / hostResult / hostRc / hostErr / hostNote.
##

declare -r AK_SUDO_REMOTE_MANY_TIMEOUT_DEFAULT=45      # per-host lend deadline, s (daemon-reload can be slow)
declare -r __AK_SUDO_MANY_CONNECT_TIMEOUT_DEFAULT=10   # ssh ConnectTimeout, s (as ak.sudo.remote-lend)
declare -r __AK_SUDO_MANY_POLL_SEC=0.2                 # result polling step — zsh has no `wait -n`
declare -r __AK_SUDO_MANY_DETAIL_LINES=5               # host output lines shown under a failure
declare -r __AK_SUDO_MANY_RC_CANCELLED=130             # password prompt cancelled (Ctrl-C / empty)
declare -r __AK_SUDO_MANY_HOST_RE='^[A-Za-z0-9._@-]+$'
declare -r __AK_SUDO_MANY_NOISE_RE='no job control|cannot set terminal process group|^[[:space:]]*$'
# shellcheck disable=SC2016  # expanded when the trap fires, not here
declare -r __AK_SUDO_MANY_ON_INT='kill $(jobs -p) 2> /dev/null; exit 130'
declare -r __AK_SUDO_SECONDS_PER_MINUTE=60

# ── pure helpers ─────────────────────────────────────────────────────────────

##
# Parse `[minutes] <host>...` of ak.sudo.remote-lend-many. Pure (no ssh).
# Minutes: a leading all-digits argument, 1..1440, default AK_SUDO_DEFAULT_MINUTES.
# Hosts: split on commas and whitespace, empties dropped, duplicates removed
# (first occurrence wins). An all-digits host is refused — minutes go FIRST,
# unlike `ak.sudo.remote-lend <host> <min>`.
# @output line 1: minutes; then one host per line
# @returns 0 ok · 1 usage error (message on stderr)
##
function __ak.sudo.many.parseArgs() {
  local -r usage='Usage: ak.sudo.remote-lend-many [minutes 1..1440] <host>...  (e.g. ak.sudo.remote-lend-many 20 h1 h2)'
  local mins="${AK_SUDO_DEFAULT_MINUTES}"
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    if ! __ak.sudo.validMinutes "$1"; then
      ak.sh.err "ak.sudo.remote-lend-many: invalid minutes '$1' — expected an integer 1..1440."
      return 1
    fi
    mins="$1"
    shift
  fi

  local -a hosts=()
  local seen=' ' host=''
  while IFS= read -r host; do
    [[ -z "${host}" ]] && continue
    if [[ "${host}" =~ ^[0-9]+$ ]]; then
      ak.sh.err "ak.sudo.remote-lend-many: '${host}' is not a host — minutes go FIRST: ak.sudo.remote-lend-many 20 h1 h2"
      return 1
    fi
    if [[ "${host}" == -* || ! "${host}" =~ ${__AK_SUDO_MANY_HOST_RE} ]]; then
      ak.sh.err "ak.sudo.remote-lend-many: invalid host '${host}' — allowed: A-Z a-z 0-9 . _ @ - (not leading '-')."
      return 1
    fi
    [[ "${seen}" == *" ${host} "* ]] && continue
    seen+="${host} "
    hosts+=("${host}")
  done < <(__ak.sudo.many.splitHosts "$@")

  if (( ${#hosts[@]} == 0 )); then
    ak.sh.err "${usage}"
    return 1
  fi
  printf '%s\n' "${mins}" "${hosts[@]}"
}

# Echo the host words of the arguments one per line: commas, spaces and tabs
# all separate (empty words included — the caller drops them).
function __ak.sudo.many.splitHosts() {
  # shellcheck disable=SC2020  # a char-for-char map: comma, space, tab → newline
  printf '%s\n' "$@" | tr ', \t' '\n\n\n'
}

# Echo the deadline_epoch of a porcelain line, or nothing when it has none.
# @param $1 porcelain line (`granted=1 deadline_epoch=<epoch> lend_api=1`)
function __ak.sudo.many.porcelainDeadline() {
  local -r line="${1:-}"
  local dl="${line##*deadline_epoch=}"
  [[ "${dl}" == "${line}" ]] && return 0
  dl="${dl%%[![:digit:]]*}"
  [[ -n "${dl}" ]] && printf '%s\n' "${dl}"
  return 0
}

# Echo the first porcelain line (`granted=…`) of a host's stdout — a login
# shell may print motd/rc noise around it.
# @param $1 stdout
function __ak.sudo.many.porcelainLine() {
  printf '%s\n' "${1:-}" | grep -E '^granted=[01]' | head -n 1
}

##
# Classify a PROBE result. Pure. The probe is a hint, not a fact: a grant seen
# here may vanish before the lend (docs/tasks/00f §2a).
# @param $1 rc   ssh exit code of the probe
# @param $2 out  its stdout: the porcelain line + `nopasswd=0|1`
# @output unreachable | no_ak | failed | outdated | granted:<deadlineEpoch> | nopasswd | need
#         (the epoch after `granted:` may be empty)
##
function __ak.sudo.many.probeState() {
  local -r rc="${1:-}"
  local -r out="${2:-}"
  local line=''
  line="$(__ak.sudo.many.porcelainLine "${out}")"

  case "${rc}" in
    124 | 255) printf 'unreachable\n'; return 0 ;;
    127) printf 'no_ak\n'; return 0 ;;
    0) ;;
    *) printf 'failed\n'; return 0 ;;
  esac
  # Porcelain parsers ignore unknown fields; `lend_api=1` is the capability
  # marker of an ak.sudo.lend that understands --password-fd.
  if [[ " ${line} " != *' lend_api=1 '* ]]; then
    printf 'outdated\n'
    return 0
  fi
  if [[ "${line}" == granted=1* ]]; then
    printf 'granted:%s\n' "$(__ak.sudo.many.porcelainDeadline "${line}")"
    return 0
  fi
  if printf '%s\n' "${out}" | grep -qx 'nopasswd=1'; then
    printf 'nopasswd\n'
    return 0
  fi
  printf 'need\n'
}

##
# Classify a LEND result. Pure. A failed probe state passes through unchanged.
# @param $1 probeState  see __ak.sudo.many.probeState
# @param $2 rc          ssh exit code of the lend (AK_SUDO_RC_* from the host)
# @param $3 out         its stdout: an optional `lend_auth=rejected` line, then
#                       the porcelain line printed AFTER the lend
# @output ok | relent | shortened | relent_other_password | bad_password |
#         grant_vanished | needs_tty | no_cache | outdated | no_ak |
#         unreachable | timeout | failed   (`skipped` is set by the caller)
##
function __ak.sudo.many.classify() {
  local -r probeState="${1:-}"
  local -r rc="${2:-}"
  local -r out="${3:-}"

  case "${probeState}" in
    unreachable | no_ak | outdated | failed) printf '%s\n' "${probeState}"; return 0 ;;
  esac
  case "${rc}" in
    124) printf 'timeout\n'; return 0 ;;
    255) printf 'unreachable\n'; return 0 ;;
    127) printf 'no_ak\n'; return 0 ;;
    "${AK_SUDO_RC_BAD_PASSWORD}") printf 'bad_password\n'; return 0 ;;
    "${AK_SUDO_RC_NEEDS_TTY}") printf 'needs_tty\n'; return 0 ;;
    "${AK_SUDO_RC_NO_CACHE}") printf 'no_cache\n'; return 0 ;;
    "${AK_SUDO_RC_NO_PASSWORD}") printf 'grant_vanished\n'; return 0 ;;
    0) ;;
    *) printf 'failed\n'; return 0 ;;
  esac

  local line=''
  line="$(__ak.sudo.many.porcelainLine "${out}")"
  if [[ "${line}" != granted=1* ]]; then
    printf 'failed\n'
    return 0
  fi
  if printf '%s\n' "${out}" | grep -qx 'lend_auth=rejected'; then
    printf 'relent_other_password\n'
    return 0
  fi
  if [[ "${probeState}" != granted:* ]]; then
    printf 'ok\n'
    return 0
  fi

  # Re-lend sets the window to now+N, it does NOT add N: a longer window shrinks.
  local -r prev="${probeState#granted:}"
  local next=''
  next="$(__ak.sudo.many.porcelainDeadline "${line}")"
  if [[ -n "${prev}" && -n "${next}" ]] && (( next < prev )); then
    printf 'shortened\n'
    return 0
  fi
  printf 'relent\n'
}

# Format an epoch with a date(1) format in the LOCAL zone. BSD `-r` first
# (GNU's `-r` means "reference FILE" and just fails), GNU `-d @…` second.
# @param $1 epoch  @param $2 format without the leading '+'
function __ak.sudo.many.date() {
  date -r "$1" "+$2" 2> /dev/null || date -d "@$1" "+$2" 2> /dev/null
}

##
# Echo `HH:MM:SS` of <epoch> in the local zone, prefixed with `YYYY-MM-DD ` when
# its local date differs from that of <now>. Pure given its inputs.
# @param $1 epoch  @param $2 now (epoch)
##
function __ak.sudo.many.formatClock() {
  local -r epoch="$1"
  local -r now="$2"
  local day='' today='' clock=''
  day="$(__ak.sudo.many.date "${epoch}" '%Y-%m-%d')"
  today="$(__ak.sudo.many.date "${now}" '%Y-%m-%d')"
  clock="$(__ak.sudo.many.date "${epoch}" '%H:%M:%S')"
  if [[ "${day}" != "${today}" ]]; then
    printf '%s %s' "${day}" "${clock}"
    return 0
  fi
  printf '%s' "${clock}"
}

##
# Echo `<N>m  until <clock>` for a deadline: minutes left rounded to the
# nearest minute, the clock as in __ak.sudo.many.formatClock. Pure given its
# inputs — `now` is a parameter so the format is testable without hosts.
# @param $1 deadlineEpoch  @param $2 nowEpoch
# @returns 1 when either epoch is not a number
##
function __ak.sudo.many.formatDeadline() {
  local -r dl="${1:-}"
  local -r now="${2:-}"
  [[ "${dl}" =~ ^[0-9]+$ && "${now}" =~ ^[0-9]+$ ]] || return 1

  local -i left=$(( dl - now ))
  (( left < 0 )) && left=0
  local -r -i roundedMin=$(( (left + __AK_SUDO_SECONDS_PER_MINUTE / 2) / __AK_SUDO_SECONDS_PER_MINUTE ))
  printf '%dm  until %s' "${roundedMin}" "$(__ak.sudo.many.formatClock "${dl}" "${now}")"
}

##
# Echo the one-phrase reason of a failed host. Pure.
# @param $1 class  @param $2 host  @param $3 rc  @param $4 stderr
# @param $5 note   skipped: why (see lendRound) · grant_vanished: why not retried
##
function __ak.sudo.many.reason() {
  local -r class="$1"
  local -r host="$2"
  local -r rc="$3"
  local -r err="$4"
  local -r note="${5:-}"
  local -r hostKeyRe='Host key verification failed|host key is known|REMOTE HOST IDENTIFICATION HAS CHANGED'

  case "${class}" in
    bad_password) printf 'password rejected' ;;
    skipped) printf 'skipped — %s' "${note}" ;;
    grant_vanished) printf 'grant vanished since the probe, %s' "${note:-sudo password needed}" ;;
    needs_tty) printf 'sudo needs a terminal here (requiretty / PAM) — use: ak.sudo.remote-lend %s' "${host}" ;;
    no_cache) printf 'password accepted, but the sudo credential cache is not reusable (timestamp_timeout=0 / timestamp_type?)' ;;
    outdated) printf 'ankor-shell outdated — run the fleet update first' ;;
    no_ak) printf 'ankor-shell not installed' ;;
    timeout) printf 'timed out — state UNKNOWN, check: ak.sudo.remote-status %s' "${host}" ;;
    unreachable)
      if [[ "${err}" =~ ${hostKeyRe} ]]; then
        printf 'host key not in known_hosts — ssh %s once first' "${host}"
      elif [[ "${err}" == *'Permission denied'* ]]; then
        printf 'ssh auth failed (key not in the agent?)'
      elif [[ "${rc}" == '124' ]]; then
        printf 'unreachable (timeout)'
      else
        printf 'unreachable (ssh rc=%s)' "${rc}"
      fi
      ;;
    *) printf 'failed (rc=%s)' "${rc:-?}" ;;
  esac
}

##
# Echo the trailing note of a ✔ line. Pure.
# @param $1 class  @param $2 probeState  @param $3 isCanary (1/'')  @param $4 now
##
function __ak.sudo.many.successNote() {
  local -r class="$1"
  local -r prev="${2#granted:}"
  local -r isCanary="${3:-}"
  local -r now="$4"

  case "${class}" in
    ok) printf 'lent%s' "${isCanary:+ (password checked here first)}" ;;
    shortened) printf 're-lent — window SHORTENED from %s' "$(__ak.sudo.many.formatClock "${prev}" "${now}")" ;;
    relent_other_password) printf 'password rejected here, re-lent on the live grant' ;;
    *)
      if [[ "${prev}" =~ ^[0-9]+$ ]]; then
        printf 're-lent (was %s)' "$(__ak.sudo.many.formatClock "${prev}" "${now}")"
      else
        printf 're-lent'
      fi
      ;;
  esac
}

# Echo the last significant lines of a host's output, indented: ANSI colours
# and CRs stripped, `bash -i` noise dropped. Pure.
# @param $1 text
function __ak.sudo.many.formatDetails() {
  printf '%s\n' "${1:-}" \
    | sed -e $'s/\e\\[[0-9;]*[A-Za-z]//g' -e $'s/\r$//' \
    | grep -Ev "${__AK_SUDO_MANY_NOISE_RE}" \
    | tail -n "${__AK_SUDO_MANY_DETAIL_LINES}" \
    | sed 's/^/    /'
}

# True for the classes that end with a live grant on the host.
function __ak.sudo.many.isSuccess() {
  case "${1:-}" in
    ok | relent | shortened | relent_other_password) return 0 ;;
  esac
  return 1
}

# Echo the arguments joined with ", ".
function __ak.sudo.many.join() {
  local joined='' item=''
  for item in "$@"; do
    joined+="${joined:+, }${item}"
  done
  printf '%s' "${joined}"
}

# ── orchestration (shares the run state of __ak.sudo.many.run) ──────────────

# Probe <host>... in parallel WITHOUT a password and fill hostState / hostRc /
# hostErr. Strict host-key checking: the lend that follows sends a password,
# and TOFU on a never-seen key would hand it to a MITM.
function __ak.sudo.many.probe() {
  local -r remoteCmd="bash -lic 'command -v ak.sudo.status > /dev/null || exit 127; ak.sudo.status --porcelain; sudo -n true 2> /dev/null && echo nopasswd=1 || echo nopasswd=0'"
  local -r dir="${tmpDir}/probe"
  mkdir -p "${dir}" || return 1
  __ak.sudo.remote.pollAll "${dir}" "${AK_SUDO_REMOTE_ALL_TIMEOUT:-${AK_SUDO_REMOTE_POLL_TIMEOUT_DEFAULT}}" \
    0 "${remoteCmd}" "$@"

  local -i i=0
  local host='' rc=''
  for host in "$@"; do
    i+=1
    rc="$(cat "${dir}/${i}.rc" 2> /dev/null)"
    hostRc[${host}]="${rc}"
    hostErr[${host}]="$(cat "${dir}/${i}.err" 2> /dev/null)"
    hostState[${host}]="$(__ak.sudo.many.probeState "${rc}" "$(cat "${dir}/${i}.out" 2> /dev/null)")"
  done
}

# Ask for the sudo password into the CALLER's `pw` (dynamic scope: a command
# substitution could only hand it back through yet another copy). Ctrl-C is a
# SIGINT to this process too — a no-op trap keeps the run alive so the caller
# decides what a cancel means.
# @param $1 prompt text
# @returns 0 got one · 130 cancelled (Ctrl-C or empty input) · 1 no terminal
function __ak.sudo.many.askPassword() {
  trap ':' INT
  pw="$(ak.sh.readSecret "$1")"
  local -r rc=$?
  # shellcheck disable=SC2064  # the constant IS the trap code, expanding it now is the point
  trap "${__AK_SUDO_MANY_ON_INT}" INT

  (( rc == 0 )) || return "${rc}"
  [[ -n "${pw}" ]] || return "${__AK_SUDO_MANY_RC_CANCELLED}"
  printf '\n'
  return 0
}

# Start the lend on <host> in the background. Results land in
# <tmpDir>/<phase>-<host>.{out,err,rc}; `.rc` is written LAST and atomically,
# its existence means "done". The password goes to ssh's stdin through a pipe
# (the host moves it to fd 3); no password → an empty pipe (EOF).
# @param $1 phase  @param $2 host  @param $3 password (optional)
function __ak.sudo.many.launch() {
  local -r phase="$1"
  local -r host="$2"
  local pw="${3:-}"
  local -r base="${tmpDir}/${phase}-${host}"
  (
    { [[ -n "${pw}" ]] && printf '%s\n' "${pw}"; } \
      | ak.sh.timeout "${timeoutSec}" ssh -T -o BatchMode=yes -o "ConnectTimeout=${connectSec}" \
          -- "${host}" "${lendCmd}" > "${base}.out" 2> "${base}.err"
    echo $? > "${base}.rc.tmp" && mv -f "${base}.rc.tmp" "${base}.rc"
  ) 2> /dev/null &   # the job's own notices (e.g. "Killed") — ssh stderr is captured above
  unset pw
}

# Record the finished lend of <host>: classify it, print ✔ right away (failures
# wait for the summary).
# @param $1 phase  @param $2 host  @param $3 canary host ('' if none)
function __ak.sudo.many.record() {
  local -r phase="$1"
  local -r host="$2"
  local -r canary="$3"
  local -r base="${tmpDir}/${phase}-${host}"
  local rc='' out='' class=''
  rc="$(cat "${base}.rc" 2> /dev/null)"
  out="$(cat "${base}.out" 2> /dev/null)"
  class="$(__ak.sudo.many.classify "${hostState[${host}]:-}" "${rc}" "${out}")"
  hostResult[${host}]="${class}"
  hostRc[${host}]="${rc}"
  hostErr[${host}]="$(cat "${base}.err" 2> /dev/null)"

  __ak.sudo.many.isSuccess "${class}" || return 0
  local isCanary=''
  [[ "${host}" == "${canary}" ]] && isCanary=1
  __ak.sudo.many.printSuccess "${host}" "${class}" "${out}" "${isCanary}"
}

# Print one ✔ line: green, yellow when the window shrank or the password was
# rejected here. Column widths are fixed up front, so streaming stays aligned.
# @param $1 host  @param $2 class  @param $3 lend stdout  @param $4 isCanary
function __ak.sudo.many.printSuccess() {
  local -r host="$1"
  local -r class="$2"
  local -r now="$(date +%s)"
  local dl='' when='deadline unknown'
  dl="$(__ak.sudo.many.porcelainDeadline "$(__ak.sudo.many.porcelainLine "$3")")"
  [[ -n "${dl}" ]] && when="$(__ak.sudo.many.formatDeadline "${dl}" "${now}")"

  local color="${cGreen}"
  [[ "${class}" == 'shortened' || "${class}" == 'relent_other_password' ]] && color="${cYellow}"
  printf '%s✔ %-*s  %-*s  %s%s\n' "${color}" "${width}" "${host}" "${whenWidth}" "${when}" \
    "$(__ak.sudo.many.successNote "${class}" "${hostState[${host}]:-}" "$4" "${now}")" "${cNC}"
}

# Poll until every <host> of <phase> has its `.rc`, recording each as it lands
# (✔ lines stream out in completion order).
# @param $1 phase  @param $2 canary host ('' if none)  @param $3.. hosts
function __ak.sudo.many.await() {
  local -r phase="$1"
  local -r canary="$2"
  shift 2
  local -a pending=("$@")
  local -a still=()
  local host=''

  while (( ${#pending[@]} > 0 )); do
    still=()
    for host in "${pending[@]}"; do
      if [[ -f "${tmpDir}/${phase}-${host}.rc" ]]; then
        __ak.sudo.many.record "${phase}" "${host}" "${canary}"
      else
        still+=("${host}")
      fi
    done
    pending=("${still[@]}")
    (( ${#pending[@]} > 0 )) && sleep "${__AK_SUDO_MANY_POLL_SEC}"
  done
  wait
}

##
# One lend round: prove the password on ONE canary host (sequentially, first
# host that needs it; the next one takes over only if the canary never got to
# check it), then send it to ALL remaining hosts in one parallel wave — hosts
# that did not need it included (a grant seen by the probe may have vanished,
# docs/tasks/00f §2a). A rejected password is never sent anywhere else:
# faillock counts every attempt, on every host.
# @param $1 phase     file prefix of this round
# @param $2 allNeed   1 = every host needs the password (the retry round)
# @param $3 password  '' when none was asked for
# @param $4.. hosts
##
function __ak.sudo.many.lendRound() {
  local -r phase="$1"
  local -r allNeed="$2"
  local pw="$3"
  shift 3

  local -a needList=() freeList=() restNeed=()
  local host=''
  for host in "$@"; do
    if (( allNeed )) || [[ "${hostState[${host}]:-}" == 'need' ]]; then
      needList+=("${host}")
    else
      freeList+=("${host}")
    fi
  done

  # skipReason, once set, stops the password: the remaining hosts that need it
  # are marked `skipped` with that reason. Only a canary that never got to
  # check the password (unreachable, no ankor-shell, requiretty…) hands the
  # role to the next host — any other failure after the password was sent is
  # NOT proof and must not cost faillock attempts across the fleet.
  local canary='' skipReason=''
  for host in "${needList[@]}"; do
    if [[ -n "${canary}" ]]; then
      restNeed+=("${host}")
    elif [[ -n "${skipReason}" ]]; then
      hostResult[${host}]='skipped'
      hostNote[${host}]="${skipReason}"
    else
      __ak.sudo.many.launch "${phase}" "${host}" "${pw}"
      __ak.sudo.many.await "${phase}" "${host}" "${host}"
      case "${hostResult[${host}]}" in
        ok | relent | shortened | no_cache) canary="${host}" ;;   # password accepted
        bad_password) skipReason="password rejected on ${host}" ;;
        unreachable | timeout | no_ak | outdated | needs_tty) ;;  # not checked — next canary
        *) skipReason="password not proven on ${host} (${hostResult[${host}]}, rc=${hostRc[${host}]:-?})" ;;
      esac
    fi
  done
  # Only a password proven on the canary travels further. A no_cache canary
  # proved it but cannot lend itself — it stays ✘, the wave still gets the password.
  [[ -z "${canary}" ]] && pw=''

  local -a wave=("${restNeed[@]}" "${freeList[@]}")
  for host in "${wave[@]}"; do
    __ak.sudo.many.launch "${phase}" "${host}" "${pw}"
  done
  unset pw
  (( ${#wave[@]} > 0 )) && __ak.sudo.many.await "${phase}" "${canary}" "${wave[@]}"
  return 0
}

# Print the ✘ block (input order) and the summary line.
# @param $@ hosts
# @returns 0 all lent · 1 at least one failed
function __ak.sudo.many.printSummary() {
  local -i nOk=0 nFail=0
  local host='' class='' details=''
  for host in "$@"; do
    class="${hostResult[${host}]:-failed}"
    if __ak.sudo.many.isSuccess "${class}"; then
      nOk+=1
      continue
    fi
    nFail+=1
    printf '%s✘ %-*s  %s%s\n' "${cRed}" "${width}" "${host}" \
      "$(__ak.sudo.many.reason "${class}" "${host}" "${hostRc[${host}]:-}" "${hostErr[${host}]:-}" "${hostNote[${host}]:-}")" "${cNC}"
    details="$(__ak.sudo.many.formatDetails "${hostErr[${host}]:-}")"
    [[ -n "${details}" ]] && printf '%s\n' "${details}"
  done
  printf '\n%d lent / %d failed\n' "${nOk}" "${nFail}"
  (( nFail == 0 ))
}

# The whole run, inside the subshell that owns tmpDir and the traps.
# @param $1 minutes  @param $2.. hosts (parsed, unique)
function __ak.sudo.many.run() {
  local -r mins="$1"
  shift
  local -a hosts=("$@")
  local -A hostState=()
  local -A hostResult=()
  local -A hostRc=()
  local -A hostErr=()
  local -A hostNote=()
  local -r timeoutSec="${AK_SUDO_REMOTE_MANY_TIMEOUT:-${AK_SUDO_REMOTE_MANY_TIMEOUT_DEFAULT}}"
  local -r connectSec="${AK_SUDO_REMOTE_TIMEOUT:-${__AK_SUDO_MANY_CONNECT_TIMEOUT_DEFAULT}}"
  # The host's login shell moves ssh's stdin (the password pipe) to fd 3 and
  # gives `bash -lic` /dev/null — rc files never see the password. The
  # porcelain line AFTER the lend reports the real deadline.
  local -r lendCmd="bash -lic 'command -v ak.sudo.lend > /dev/null || exit 127; ak.sudo.lend --password-fd 3 ${mins}; rc=\$?; ak.sudo.status --porcelain; exit \$rc' 3<&0 0< /dev/null"
  local -r whenSample='m  until 2000-01-01 00:00:00'
  local -r -i whenWidth=$(( ${#mins} + ${#whenSample} ))
  local -i width=0
  local host=''
  for host in "${hosts[@]}"; do
    (( ${#host} > width )) && width=${#host}
  done

  local cGreen='' cRed='' cYellow='' cNC=''
  if [[ -t 1 ]]; then
    cGreen="${AK_COLOR_Green}"
    cRed="${AK_COLOR_Red}"
    cYellow="${AK_COLOR_Yellow}"
    cNC="${AK_COLOR_NC}"
  fi

  __ak.sudo.many.probe "${hosts[@]}" || return 1

  local -a needHosts=() activeHosts=()
  for host in "${hosts[@]}"; do
    case "${hostState[${host}]}" in
      need) needHosts+=("${host}"); activeHosts+=("${host}") ;;
      granted:* | nopasswd) activeHosts+=("${host}") ;;
      *) hostResult[${host}]="$(__ak.sudo.many.classify "${hostState[${host}]}" '' '')" ;;
    esac
  done

  local pw=''
  local -i askRc=0
  if (( ${#needHosts[@]} > 0 )); then
    __ak.sudo.many.askPassword "sudo password for ${#needHosts[@]} host(s) ($(__ak.sudo.many.join "${needHosts[@]}")): "
    askRc=$?
    if (( askRc != 0 )); then
      unset pw
      ak.sh.err "ak.sudo.remote-lend-many: cancelled — no host was changed."
      return "${askRc}"
    fi
  fi
  (( ${#activeHosts[@]} > 0 )) && __ak.sudo.many.lendRound l1 0 "${pw}" "${activeHosts[@]}"
  unset pw

  # Retry round (at most one) for grants that vanished since the probe. The
  # password is asked AGAIN rather than kept "just in case".
  local -a vanished=()
  for host in "${hosts[@]}"; do
    [[ "${hostResult[${host}]:-}" == 'grant_vanished' ]] && vanished+=("${host}")
  done
  if (( ${#vanished[@]} > 0 )); then
    local pw=''
    if __ak.sudo.many.askPassword "grant vanished on $(__ak.sudo.many.join "${vanished[@]}") since the probe — sudo password needed: "; then
      __ak.sudo.many.lendRound l2 1 "${pw}" "${vanished[@]}"
    else
      for host in "${vanished[@]}"; do hostNote[${host}]='password not given'; done
    fi
    unset pw
  fi

  __ak.sudo.many.printSummary "${hosts[@]}"
}

##
# Lend passwordless sudo on SEVERAL hosts with ONE password: asked once
# (hidden, `*` per char, paste works) and only if a host needs it; checked on
# ONE canary host first; then sent to the rest in parallel. ✔ lines stream in
# as hosts answer, ✘ lines (with the host's last output lines) follow as a
# block, then `N lent / M failed`.
#
# Needs ankor-shell with `lend_api=1` (ak.sudo.lend --password-fd) on every
# host — older hosts are reported as `outdated`, untouched. Host keys must
# already be in known_hosts: StrictHostKeyChecking is NOT relaxed here.
# Never run it through an agent: without a tty the prompt refuses, by design.
#
# @param $1 minutes (optional, FIRST) 1..1440, default AK_SUDO_DEFAULT_MINUTES —
#           sent to every host explicitly, so all windows are equal
# @param $@ hosts — ~/.ssh/config aliases or user@host, space or comma separated
# @env AK_SUDO_REMOTE_MANY_TIMEOUT per-host lend deadline in seconds (default 45)
# @env AK_SUDO_REMOTE_ALL_TIMEOUT  per-host probe deadline in seconds (default 15)
# @env AK_SUDO_REMOTE_TIMEOUT      ssh ConnectTimeout of the lend (default 10)
# @returns 0 all hosts lent · 1 any failure or usage error · 130 prompt cancelled
#
# @example
#   ak.sudo.remote-lend-many 20 vps-alpha vps-bravo vps-charlie
#   ak.sudo.remote-lend-many vps-alpha,vps-bravo          # default window
##
function ak.sudo.remote-lend-many() {
  # xtrace would print the password — off for this call only.
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt localoptions noxtrace
  else
    local -
    set +x
  fi

  local parsed=''
  parsed="$(__ak.sudo.many.parseArgs "$@")" || return 1
  local mins='' host=''
  local -a hosts=()
  {
    IFS= read -r mins
    while IFS= read -r host; do hosts+=("${host}"); done
  } < <(printf '%s\n' "${parsed}")

  # Subshell: the EXIT trap removes the temp dir on every exit path, and the
  # per-host jobs stay silent in interactive shells.
  (
    local tmpDir=''
    tmpDir="$(mktemp -d "${TMPDIR:-/tmp}/ak-sudo-lend-many.XXXXXX")" || {
      ak.sh.err "ak.sudo.remote-lend-many: mktemp failed."
      exit 1
    }
    trap 'rm -rf "${tmpDir}"' EXIT
    # Reap the jobs BEFORE the EXIT rm (a job re-creating its .rc would leave
    # the dir behind). Ctrl-C after lends started: some hosts may already hold
    # a grant — check with ak.sudo.remote-status-all.
    # shellcheck disable=SC2064  # the constant IS the trap code, expanding it now is the point
    trap "${__AK_SUDO_MANY_ON_INT}" INT
    trap 'kill $(jobs -p) 2> /dev/null; exit 143' TERM
    __ak.sudo.many.run "${mins}" "${hosts[@]}"
  )
}
