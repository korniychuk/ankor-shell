#!/usr/bin/env bash

##
# ak.sudo.* — lend the CURRENT user temporary passwordless sudo, time-boxed with
# an automatic revoke as a safety net. Linux (systemd) + macOS (launchd) + sudo.
#
# Purpose: let an automation/agent (or a quick maintenance window) run privileged
# commands for a BOUNDED time WITHOUT ever sharing your password. You run
# `ak.sudo.lend` once (typing your password a single time); a transient auto-revoke
# job (systemd timer on Linux, a self-destructing LaunchDaemon on macOS) removes
# the grant after N minutes, or call `ak.sudo.revoke`.
#
# @example
#   ak.sudo.lend            # grant for 30 min (default)
#   ak.sudo.lend 120        # grant for 2 hours
#   ak.sudo.status          # is it active? when does it auto-revoke?
#   ak.sudo.revoke          # revoke now + cancel the timer
#
# Remote (ak.sudo.* on another host over SSH, with host completion):
#   ak.sudo.remote-lend HOST 60     # one-shot lend on HOST
#   ak.sudo.remote-status HOST      # grant state of one host
#   ak.sudo.remote-status-all       # overview across all ssh-config hosts
#   ak.sudo.remote-revoke HOST
#
# ak.sudo.remote-* compose the remote command locally into ONE argv string, so
# the raw form below is needed only when ankor-shell is absent LOCALLY:
#   ssh -t HOST 'bash -lic "ak.sudo.lend 60"'
#
# The OUTER quotes are mandatory. `ssh` joins its argv into ONE string that the
# remote login shell re-parses, so `ssh -t HOST bash -lic 'ak.sudo.lend 60'`
# arrives as `bash -lic ak.sudo.lend 60` — and `bash -c`'s first operand is $0,
# not $1, so the minutes would silently fall back to the default. ak.sudo.lend
# detects that exact shape and refuses (see the $0 guard below).
##

declare -r AK_SUDO_FILE="/etc/sudoers.d/99-ak-temp-sudo"
declare -r AK_SUDO_UNIT="ak-sudo-revoke"                          # Linux: transient systemd unit
declare -r AK_SUDO_LABEL="com.ankor.ak-sudo-revoke"               # macOS: launchd job label
declare -r AK_SUDO_PLIST="/Library/LaunchDaemons/${AK_SUDO_LABEL}.plist"

function __ak.sudo.preflight() {
  if ! ak.os.type.isLinux && ! ak.os.type.isMacOS; then
    ak.sh.err "ak.sudo.* supports Linux (systemd) and macOS (launchd) only."
    return 1
  fi
  if ! ak.sh.commandExists sudo; then
    ak.sh.err "ak.sudo.*: 'sudo' not found."
    return 1
  fi
  return 0
}

# Valid lend duration: integer minutes within 1..1440. Shared by ak.sudo.lend
# and ak.sudo.remote-lend — the remote wrapper validates LOCALLY, so nothing
# shell-escapable can ever reach the composed ssh command.
function __ak.sudo.validMinutes() {
  [[ "${1:-}" =~ ^[0-9]+$ ]] || return 1
  (( $1 >= 1 && $1 <= 1440 ))
}

# True if sudo currently runs WITHOUT a password — for ANY reason: an ak grant,
# a cached credential timestamp, OR a standing NOPASSWD rule we don't manage.
# Never prompts (`-n`).
function __ak.sudo.passwordless() {
  sudo -n true 2> /dev/null
}

# True if OUR temp drop-in is present — the single source of truth for an ak
# grant. Statting it needs passwordless sudo (the dir is root-owned); if sudo
# would prompt, there cannot be an active passwordless ak grant anyway, so a
# silent failure correctly reads as "absent".
function __ak.sudo.granted() {
  sudo -n test -f "${AK_SUDO_FILE}" 2> /dev/null
}

# True if the user has a STANDING NOPASSWD rule granting FULL passwordless sudo —
# one NOT lent by ak. `sudo -l` prints the effective sudoers policy, which
# reflects the RULES, not the cached credential timestamp, so this cleanly
# separates "a real standing rule" from "sudo just happens to be passwordless
# right now because of a recent sudo".
#
# Match `NOPASSWD: ALL`, NOT a bare `NOPASSWD` token: a command-SCOPED rule like
# `(root) NOPASSWD: /usr/local/sbin/foo` is passwordless for ONE command only, not
# general sudo, so it must NOT trigger the "passwordless sudo is available" warning.
# The trailing `([[:space:]]|,|$)` anchors the `ALL` keyword so a command path such
# as `/opt/INSTALL_thing` or a `NOPASSWD: ALLOW_ME` rule can't false-positive. All
# tokens are POSIX ERE — portable across GNU grep (Linux) and BSD grep (macOS).
# `NOPASSWD`/`ALL` are sudoers keywords (never localized). Callers use this only
# when __ak.sudo.granted is false, so ak's own `NOPASSWD: ALL` line can't match.
function __ak.sudo.hasStandingNopasswdRule() {
  sudo -n -l 2> /dev/null | grep -Eq 'NOPASSWD:[[:space:]]*ALL([[:space:]]|,|$)'
}

# ── auto-revoke facility (OS-abstracted) ─────────────────────────────────────

# Render the macOS self-destructing LaunchDaemon plist to stdout. Pure (no side
# effects) so it can be validated with `plutil -lint`. launchd has no one-shot
# "run in N minutes", so we bake an absolute deadline (AKDL, epoch seconds): the
# job sleeps the remaining time, removes the grant, then deregisters + deletes
# itself. Reboot-safe: RunAtLoad re-runs it and it recomputes the remaining sleep
# (or removes the grant immediately if the deadline already passed).
function __ak.sudo.macos.renderPlist() {
  local -r deadline="$1"
  # Order matters: remove the grant AND self-delete the plist BEFORE bootout —
  # bootout SIGTERMs this very process, so anything after it may never run.
  local -r job="AKDL=${deadline}; n=\$(date +%s); if [ \"\$n\" -lt \"\$AKDL\" ]; then sleep \$(( AKDL - n )); fi; /bin/rm -f '${AK_SUDO_FILE}'; /bin/rm -f '${AK_SUDO_PLIST}'; /bin/launchctl bootout system/${AK_SUDO_LABEL} 2>/dev/null"
  cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${AK_SUDO_LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>-c</string>
		<string>${job}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLIST
}

# Arm the auto-revoke safety net for <mins>. Idempotent: re-arming RESETS the
# window. Returns: 0 armed · 1 arm failed · 2 no facility (manual revoke needed).
function __ak.sudo.timer.arm() {
  local -r mins="$1"

  if ak.os.type.isLinux; then
    ak.sh.commandExists systemd-run || return 2
    # Fully clear any prior transient unit first, so re-lending just RESETS the
    # window instead of failing on "Unit already exists".
    sudo systemctl stop "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
    sudo systemctl reset-failed "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
    sudo systemd-run --quiet --unit="${AK_SUDO_UNIT}" --on-active="${mins}min" \
      /bin/rm -f "${AK_SUDO_FILE}"
    return
  fi

  # macOS
  ak.sh.commandExists launchctl || return 2
  local -r deadline="$(( $(date +%s) + mins * 60 ))"
  # Reset any prior window first so re-lending is idempotent.
  sudo launchctl bootout "system/${AK_SUDO_LABEL}" 2> /dev/null
  if ! __ak.sudo.macos.renderPlist "${deadline}" | sudo tee "${AK_SUDO_PLIST}" > /dev/null; then
    return 1
  fi
  sudo chown 0:0 "${AK_SUDO_PLIST}"      # root:wheel — launchd refuses non-root-owned daemons
  sudo chmod 0644 "${AK_SUDO_PLIST}"
  sudo launchctl bootstrap system "${AK_SUDO_PLIST}"
}

# Cancel + clean up the auto-revoke facility. Idempotent; never fails the caller.
function __ak.sudo.timer.cancel() {
  if ak.os.type.isLinux; then
    sudo systemctl stop "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
    sudo systemctl reset-failed "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
    return 0
  fi
  sudo launchctl bootout "system/${AK_SUDO_LABEL}" 2> /dev/null
  sudo rm -f "${AK_SUDO_PLIST}"
  return 0
}

# Echo an epoch as local wall-clock HH:MM. BSD date takes an epoch via `-r`,
# GNU via `-d @…`; try BSD first since GNU's `-r` means "reference FILE" and
# simply fails here. Best-effort: prints nothing if neither works, and callers
# treat that as "no suffix".
function __ak.sudo.epochClock() {
  date -r "$1" '+%H:%M' 2> /dev/null || date -d "@$1" '+%H:%M' 2> /dev/null
}

# Echo the wall-clock time <mins> from now as HH:MM — so the grant message states
# an absolute deadline, not just a duration (a wrong window is then obvious at a
# glance).
function __ak.sudo.deadlineClock() {
  __ak.sudo.epochClock "$(( $(date +%s) + $1 * 60 ))"
}

# Echo the auto-revoke deadline as epoch seconds, or nothing when unknown.
# Linux: next elapse of the transient timer; macOS: AKDL baked into the plist.
# Epoch (not "minutes left") so remote consumers can render the absolute time
# in THEIR timezone.
function __ak.sudo.timer.deadlineEpoch() {
  if ak.os.type.isLinux; then
    local next
    # systemctl show renders USec timestamps as calendar time
    # ("Fri 2026-08-01 18:42:00 UTC") — parse it back with GNU date (Linux-only path).
    next="$(systemctl show "${AK_SUDO_UNIT}.timer" -p NextElapseUSecRealtime --value 2> /dev/null)"
    [[ -n "${next}" && "${next}" != 'n/a' && "${next}" != 'infinity' ]] || return 0
    date -d "${next}" '+%s' 2> /dev/null
    return 0
  fi

  # macOS: recover the deadline epoch baked into the (world-readable) plist.
  [[ -f "${AK_SUDO_PLIST}" ]] || return 0
  grep -oE 'AKDL=[0-9]+' "${AK_SUDO_PLIST}" 2> /dev/null | head -n1 | cut -d= -f2
  return 0
}

# Echo a human " — <time> left" suffix for status, or nothing when unknown.
function __ak.sudo.timer.remaining() {
  local dl now left
  dl="$(__ak.sudo.timer.deadlineEpoch)"
  [[ "${dl}" =~ ^[0-9]+$ ]] || return 0
  now="$(date +%s)"
  (( dl > now )) || return 0
  left=$(( dl - now ))
  printf ' — %dm %ds left' "$(( left / 60 ))" "$(( left % 60 ))"
}

##
# Grant passwordless sudo to the current user for N minutes (default 30, range 1..1440).
# Prompts for your password ONCE (the first sudo). Auto-revokes via a transient
# timer (systemd on Linux, launchd on macOS); re-running re-arms the window.
# @param $1 minutes (optional, default 30)
##
function ak.sudo.lend() {
  __ak.sudo.preflight || return 1

  # Catch the collapsed-quoting remote invocation BEFORE defaulting to 30m:
  #   ssh -t HOST bash -lic 'ak.sudo.lend 15'  →  remote: bash -lic ak.sudo.lend 15
  # ssh re-joins its argv into one string, the inner quotes are gone, and `bash -c`
  # binds that trailing `15` to $0 — never to $1. Without this guard the caller
  # asks for 15m and silently gets the 30m default: a LONGER privileged window
  # than requested, the one failure direction that must never be silent.
  # $0 is a shell name/path (bash under `bash -c`, the function name under zsh),
  # so a bare number there can only come from this mistake — no false positives.
  if (( $# == 0 )) && [[ "$0" =~ ^[0-9]+$ ]]; then
    ak.sh.err "ak.sudo.lend: '$0' arrived as \$0, not as an argument — the remote command lost its quotes. Use: ssh -t HOST 'bash -lic \"ak.sudo.lend $0\"'"
    return 1
  fi
  if (( $# > 1 )); then
    ak.sh.err "Usage: ak.sudo.lend [minutes 1..1440]  (default 30) — got $# arguments"
    return 1
  fi

  local -r mins="${1:-30}"
  if ! __ak.sudo.validMinutes "${mins}"; then
    ak.sh.err "Usage: ak.sudo.lend [minutes 1..1440]  (default 30)"
    return 1
  fi

  local -r user="$(id -un)"
  local -r line="${user} ALL=(ALL) NOPASSWD: ALL"

  # Heads-up: if a STANDING NOPASSWD rule (NOT ak's) already grants passwordless
  # sudo, lending is cosmetic — ak.sudo.revoke / the auto-revoke timer only remove
  # ak's file, never that rule. A lingering credential cache is NOT a rule, so we
  # probe the policy via `sudo -l`, not `sudo -n true`.
  if ! __ak.sudo.granted && __ak.sudo.hasStandingNopasswdRule; then
    ak.sh.warn "passwordless sudo is ALREADY available via a standing sudoers rule (not ak) — ak.sudo.revoke / auto-revoke will NOT remove it."
  fi

  # Write + validate the drop-in (revert if it would break sudo).
  # Use `tee` then chmod/chown — `install /dev/stdin` is flaky with uutils-coreutils
  # (Ubuntu 26.04) over a non-tty session ("install: No such file or directory").
  if ! printf '%s\n' "${line}" | sudo tee "${AK_SUDO_FILE}" > /dev/null; then
    ak.sh.err "ak.sudo.lend: failed to write ${AK_SUDO_FILE}"
    return 1
  fi
  sudo chown 0:0 "${AK_SUDO_FILE}"       # root:root (Linux) / root:wheel (macOS) — numeric = portable
  sudo chmod 0440 "${AK_SUDO_FILE}"
  if ! sudo visudo -cf "${AK_SUDO_FILE}" > /dev/null; then
    sudo rm -f "${AK_SUDO_FILE}"
    ak.sh.err "ak.sudo.lend: sudoers validation failed — reverted, no change."
    return 1
  fi

  # (Re)arm the auto-revoke safety net. Idempotent: re-running RESETS the window.
  local -r deadlineClock="$(__ak.sudo.deadlineClock "${mins}")"
  __ak.sudo.timer.arm "${mins}"
  case "$?" in
    0)
      ak.sh.ok "passwordless sudo lent to '${user}' for ${mins}m${deadlineClock:+ (until ${deadlineClock})} — auto-revokes, or run ak.sudo.revoke" "SUDO"
      ;;
    2)
      ak.sh.warn "no auto-revoke facility available: NO auto-revoke scheduled — you MUST run ak.sudo.revoke!"
      ak.sh.ok "passwordless sudo lent to '${user}' (manual revoke required)" "SUDO"
      ;;
    *)
      ak.sh.warn "grant active but auto-revoke timer failed to arm — run ak.sudo.revoke when done!"
      ;;
  esac
}

##
# Revoke the temporary passwordless sudo immediately and cancel the auto-revoke timer.
##
function ak.sudo.revoke() {
  __ak.sudo.preflight || return 1

  # The grant IS our sudoers drop-in. Gate on the FILE, not on `sudo -n true`:
  # a standing NOPASSWD rule (or a cached timestamp) makes `sudo -n true` succeed
  # even when ak never lent anything, which made revoke falsely report success.
  # If we can't stat the file passwordlessly, there is no active ak grant to
  # revoke — bail BEFORE touching sudo so an idle call never prompts.
  if ! __ak.sudo.granted; then
    echo "ak.sudo.revoke: nothing to revoke — no ak grant (${AK_SUDO_FILE} absent)."
    if __ak.sudo.hasStandingNopasswdRule; then
      ak.sh.warn "but passwordless sudo IS still available via a rule NOT managed by ak.sudo (e.g. another /etc/sudoers.d/* file) — revoke cannot remove that."
    elif __ak.sudo.passwordless; then
      # File gone but sudo still passwordless with no standing rule = a leftover
      # credential cache (often from a just-expired ak grant). Clear it so revoke
      # is real. `sudo -k` never prompts, so this stays safe for an idle call.
      sudo -k
      ak.sh.ok "cleared a lingering sudo credential cache (no ak grant was present)" "SUDO"
    fi
    return 0
  fi

  __ak.sudo.timer.cancel
  sudo rm -f "${AK_SUDO_FILE}"

  if __ak.sudo.granted; then
    ak.sh.err "ak.sudo.revoke: ${AK_SUDO_FILE} still present — remove it manually."
    return 1
  fi

  # Invalidate sudo's cached credential timestamp. Without this, removing the
  # sudoers drop-in is NOT enough: sudo keeps honoring the cached timestamp
  # (timestamp_timeout, default 15m) so passwordless sudo stays live AFTER revoke.
  sudo -k

  # Tell the truth: if sudo is STILL passwordless after we removed our grant and
  # cleared the cached timestamp, it comes from another sudoers rule we don't
  # control — revoke could not, and cannot, take that away.
  if __ak.sudo.passwordless; then
    ak.sh.warn "ak grant removed, but passwordless sudo PERSISTS via another sudoers rule (not managed by ak.sudo) — revoke cannot take it away."
  else
    ak.sh.ok "temporary passwordless sudo revoked" "SUDO"
  fi
}

##
# Report whether the temporary grant is active and how much time remains.
# @param $1 --porcelain (optional) — ONE stable machine-readable line instead
#           of prose: `granted=1 deadline_epoch=<epoch>` (epoch omitted when
#           unknown) or `granted=0`. Consumed by ak.sudo.remote-status-all
#           over SSH — keep the format stable.
##
function ak.sudo.status() {
  __ak.sudo.preflight || return 1

  if [[ "${1:-}" == '--porcelain' ]]; then
    if __ak.sudo.granted; then
      local -r dl="$(__ak.sudo.timer.deadlineEpoch)"
      printf 'granted=1%s\n' "${dl:+ deadline_epoch=${dl}}"
    else
      printf 'granted=0\n'
    fi
    return 0
  fi

  # The grant IS the sudoers drop-in — check the file, not just `sudo -n true`,
  # which can also succeed purely from sudo's cached credential timestamp or a
  # standing NOPASSWD rule.
  if ! __ak.sudo.granted; then
    if __ak.sudo.hasStandingNopasswdRule; then
      ak.sh.warn "no ak grant — but passwordless sudo IS available via another sudoers rule (not managed by ak.sudo)."
    elif __ak.sudo.passwordless; then
      echo "inactive — ak grant revoked; sudo is still cached (run 'sudo -k' to require a password now)."
    else
      echo "inactive — no active grant (sudoers drop-in not present)"
    fi
    return 0
  fi

  local -r user="$(id -un)"
  local -r remaining="$(__ak.sudo.timer.remaining)"

  ak.sh.ok "passwordless sudo available for '${user}'${remaining}" "ACTIVE"
}

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

  local -a hosts
  hosts=()
  local host
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
    local tmpDir
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
    local host
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
    local rc out line color label dl now left
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
        dl="${line##*deadline_epoch=}"
        dl="${dl%%[![:digit:]]*}"
        now="$(date +%s)"
        if [[ "${dl}" =~ ^[0-9]+$ ]] && (( dl > now )); then
          left=$(( (dl - now + 59) / 60 ))
          label="granted — ${left}m left (until $(__ak.sudo.epochClock "${dl}"))"
        fi
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
