#!/usr/bin/env bash

##
# ak.sudo.* — lend the CURRENT user temporary passwordless sudo, time-boxed with
# an automatic revoke as a safety net. Linux (systemd) + macOS (launchd) + sudo.
#
# Purpose: let an automation/agent (or a quick maintenance window) run privileged
# commands for a BOUNDED time WITHOUT ever sharing your password. You run
# `ak.sudo.lend` once (typing your password a single time); a self-destructing
# auto-revoke job (a systemd timer + a boot-time check on Linux, a LaunchDaemon
# on macOS) removes the grant after N minutes, or call `ak.sudo.revoke`.
#
# Both auto-revoke jobs live ON DISK and survive a reboot — the deadline is a
# security boundary, and a boundary that a power cycle silently deletes is not
# one. Everything they install erases itself together with the grant.
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

# Lend window when no minutes are given. ak.sudo.remote-lend-many sends it to
# every host EXPLICITLY, so one run opens equal windows even on a host whose
# ankor-shell carries a different default.
declare -r AK_SUDO_DEFAULT_MINUTES=30

# Exit codes of `ak.sudo.lend --password-fd`. Deliberately outside the codes that
# already mean something on this path (1 generic, 124 timeout, 126/127 exec,
# 130 SIGINT, 255 ssh): the calling side classifies by CODE and shows stderr
# only as an explanation.
declare -r AK_SUDO_RC_BAD_PASSWORD=20     # sudo rejected the password
declare -r AK_SUDO_RC_NEEDS_TTY=21        # requiretty / PAM wants a terminal
declare -r AK_SUDO_RC_NO_CACHE=22         # password accepted, but no reusable credential cache
declare -r AK_SUDO_RC_NO_PASSWORD=23      # no password given and sudo is not passwordless
declare -r AK_SUDO_PASSWORD_FD_MIN=3      # 0..2 are stdio — never a password channel
declare -r AK_SUDO_PASSWORD_FD_MAX=9
# Internal (never leaves the host): authentication succeeded only because a live
# grant / rule keeps sudo passwordless — see __ak.sudo.authenticateFromFd.
declare -r __AK_SUDO_AUTH_VIA_GRANT=2

# Linux: the persistent systemd units + the helper they run. Every path here is
# created by ak.sudo.lend and removed again by the auto-revoke itself (or by
# ak.sudo.revoke) — nothing outlives the grant it belongs to.
declare -r AK_SUDO_UNIT="ak-sudo-revoke"
declare -r AK_SUDO_UNIT_DIR="/etc/systemd/system"
declare -r AK_SUDO_SERVICE_PATH="${AK_SUDO_UNIT_DIR}/${AK_SUDO_UNIT}.service"
declare -r AK_SUDO_TIMER_PATH="${AK_SUDO_UNIT_DIR}/${AK_SUDO_UNIT}.timer"
declare -r AK_SUDO_SERVICE_WANTS="${AK_SUDO_UNIT_DIR}/multi-user.target.wants/${AK_SUDO_UNIT}.service"
declare -r AK_SUDO_TIMER_WANTS="${AK_SUDO_UNIT_DIR}/timers.target.wants/${AK_SUDO_UNIT}.timer"
declare -r AK_SUDO_TIMER_STAMP="/var/lib/systemd/timers/stamp-${AK_SUDO_UNIT}.timer"
declare -r AK_SUDO_HELPER="/usr/local/sbin/ak-sudo-revoke"
declare -r AK_SUDO_SWEEP_CALENDAR="*:0/10"                        # safety-net sweep, see renderTimer

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
  local -r user="$2"
  # Dropping the lender's cached sudo timestamp is part of the revoke: the
  # NOPASSWD grant never refreshed it, but the password prompt back at lend time
  # did, so on a window shorter than timestamp_timeout (15m by default) that
  # stale cache would outlive the grant. ak.sudo.revoke clears it with `sudo -k`;
  # the unattended path must not be weaker. Both layouts of sudo's cache are
  # tried (a per-user FILE in older sudo, a ts/ directory since 1.9).
  local -r dropCache="/bin/rm -f '/var/db/sudo/ts/${user}' '/var/db/sudo/${user}'"
  # Order matters: remove the grant AND self-delete the plist BEFORE bootout —
  # bootout SIGTERMs this very process, so anything after it may never run.
  local -r job="AKDL=${deadline}; n=\$(date +%s); if [ \"\$n\" -lt \"\$AKDL\" ]; then sleep \$(( AKDL - n )); fi; /bin/rm -f '${AK_SUDO_FILE}'; ${dropCache}; /bin/rm -f '${AK_SUDO_PLIST}'; /bin/launchctl bootout system/${AK_SUDO_LABEL} 2>/dev/null"
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

# Render the Linux auto-revoke helper to stdout (pure — no side effects, so it
# can be read or diffed before it is installed).
#
# ONE script serves BOTH triggers of ak-sudo-revoke.service — the deadline timer
# and every boot — which is why it is deadline-AWARE rather than a blind `rm`:
# fired by the timer it removes an expired grant, run at boot it removes a grant
# only if its window really has ended. A grant carrying no `# AKDL=` deadline is
# treated as expired: unenforceable means gone, not immortal.
# @param $1 the user the grant was lent to (owner of the sudo timestamp cache)
function __ak.sudo.linux.renderHelper() {
  local -r user="$1"
  cat <<HELPER
#!/bin/sh
# ak.sudo auto-revoke — generated by ak.sudo.lend, deletes itself with the grant.
# Do NOT edit: the next ak.sudo.lend overwrites this file.
set -u

grant='${AK_SUDO_FILE}'
deadline=\$(sed -n 's/^# AKDL=\([0-9][0-9]*\)\$/\1/p' "\$grant" 2> /dev/null | head -n1)

# Still inside the window — this is a boot-time (or sweep) run, not the deadline.
if [ -f "\$grant" ] && [ -n "\$deadline" ] && [ "\$(date +%s)" -lt "\$deadline" ]; then
  exit 0
fi

rm -f "\$grant"

# The NOPASSWD grant itself never refreshed sudo's timestamp, but the password
# prompt back at lend time did — on a window shorter than timestamp_timeout (15m
# by default) that stale cache would outlive the grant. ak.sudo.revoke clears it
# with \`sudo -k\`; the unattended path must not be weaker. Best effort: the cache
# location differs across distros and sudo versions, so try each known one.
rm -f /run/sudo/ts/'${user}' /var/run/sudo/ts/'${user}' /var/db/sudo/ts/'${user}' /var/lib/sudo/ts/'${user}' 2> /dev/null

# Nothing left to guard: unhook from boot, then erase every trace of this window
# (this script last — the shell keeps its open fd, so it finishes fine).
rm -f '${AK_SUDO_TIMER_WANTS}' '${AK_SUDO_SERVICE_WANTS}' '${AK_SUDO_TIMER_STAMP}'
rm -f '${AK_SUDO_TIMER_PATH}' '${AK_SUDO_SERVICE_PATH}' '${AK_SUDO_HELPER}'
exit 0
HELPER
}

# Render the Linux revoke service unit to stdout (pure).
function __ak.sudo.linux.renderService() {
  cat <<UNIT
[Unit]
Description=ak.sudo — revoke the temporary passwordless sudo grant when its window ends
# The helper erases itself along with the grant; without this condition a
# leftover enablement symlink would try to start a unit whose script is gone.
ConditionPathExists=${AK_SUDO_HELPER}

[Service]
Type=oneshot
ExecStart=/bin/sh ${AK_SUDO_HELPER}

[Install]
# The timer covers a running system; this covers the boot AFTER a shutdown that
# spanned the deadline — the exact case in which the old transient timer died.
WantedBy=multi-user.target
UNIT
}

# Render the Linux revoke timer unit to stdout (pure).
# @param $1 the deadline as a systemd calendar spec, in the SYSTEM's local time
#           (that is how OnCalendar reads a spec without a zone suffix, and the
#           suffix needs systemd >= 252 — too new to rely on).
function __ak.sudo.linux.renderTimer() {
  local -r calendar="$1"
  cat <<UNIT
[Unit]
Description=ak.sudo — deadline of the temporary passwordless sudo grant

[Timer]
OnCalendar=${calendar}
# Safety net: a sweep every 10 minutes. The helper is deadline-aware, so a sweep
# inside the window is a no-op — it exists so that one absolute wall-clock
# instant is never the ONLY thing between a closed window and an open-ended root
# grant (a DST fold can swallow a local instant outright).
OnCalendar=${AK_SUDO_SWEEP_CALENDAR}
# A revoke is a security boundary — do not let the default 1min slack move it.
AccuracySec=1s
# Catch up at boot when the deadline passed while the machine was off.
Persistent=true

[Install]
WantedBy=timers.target
UNIT
}

# Install + (re)arm the persistent Linux auto-revoke units for <deadlineEpoch>.
#
# Persistent ON DISK on purpose: the previous implementation armed a transient
# unit with `systemd-run`, and transient units live only in the RUNNING manager —
# a reboot silently erased the auto-revoke while the sudoers drop-in stayed on
# disk, turning a 30-minute grant into a permanent one (task 00c).
# Returns: 0 armed · 1 arm failed · 2 no systemd.
# @param $1 deadline epoch seconds
function __ak.sudo.linux.arm() {
  local -r deadline="$1"

  ak.sh.commandExists systemctl || return 2

  # `env -u TZ`: OnCalendar without a zone suffix means the SYSTEM's local time,
  # so the epoch must be rendered in the system zone — never in a TZ that an ssh
  # session happened to forward, which would move the deadline by whole hours.
  local -r calendar="$(env -u TZ date -d "@${deadline}" '+%Y-%m-%d %H:%M:%S' 2> /dev/null)"
  if [[ -z "${calendar}" ]]; then
    ak.sh.err "ak.sudo: could not render deadline '${deadline}' as a systemd calendar spec."
    return 1
  fi

  sudo mkdir -p "$(dirname "${AK_SUDO_HELPER}")" || return 1
  __ak.sudo.linux.renderHelper "$(id -un)" | sudo tee "${AK_SUDO_HELPER}" > /dev/null || return 1
  sudo chown 0:0 "${AK_SUDO_HELPER}" || return 1
  sudo chmod 0755 "${AK_SUDO_HELPER}" || return 1
  __ak.sudo.linux.renderService | sudo tee "${AK_SUDO_SERVICE_PATH}" > /dev/null || return 1
  __ak.sudo.linux.renderTimer "${calendar}" | sudo tee "${AK_SUDO_TIMER_PATH}" > /dev/null || return 1
  sudo chmod 0644 "${AK_SUDO_SERVICE_PATH}" "${AK_SUDO_TIMER_PATH}" || return 1

  # Drop the catch-up stamp of any PREVIOUS window: `Persistent=true` reads it as
  # "when this timer last fired", and it must not describe a window we replaced.
  sudo rm -f "${AK_SUDO_TIMER_STAMP}"

  sudo systemctl daemon-reload || return 1
  # A running timer keeps its OLD deadline until restarted, and `enable --now` on
  # an already-active unit is a no-op — so stop first, then arm. These two may
  # legitimately fail (nothing armed yet); the `enable`s below decide success.
  # They also clear a leftover TRANSIENT unit from a pre-00c ankor-shell.
  sudo systemctl stop "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
  sudo systemctl reset-failed "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
  sudo systemctl enable --quiet "${AK_SUDO_UNIT}.service" || return 1
  sudo systemctl enable --quiet --now "${AK_SUDO_UNIT}.timer" || return 1

  # An armed timer is the entire point of this function — verify, never assume.
  sudo systemctl is-active --quiet "${AK_SUDO_UNIT}.timer" || return 1
  return 0
}

# Arm the auto-revoke safety net for the window ending at <deadlineEpoch>.
# The caller computes the epoch once and passes it in, so the armed job, the
# recorded deadline and the message a user reads cannot disagree.
# Idempotent: re-arming RESETS the window.
# Returns: 0 armed · 1 arm failed · 2 no facility (manual revoke needed).
# @param $1 deadline epoch seconds
function __ak.sudo.timer.arm() {
  local -r deadline="$1"

  if ak.os.type.isLinux; then
    __ak.sudo.linux.arm "${deadline}"
    return
  fi

  # macOS
  ak.sh.commandExists launchctl || return 2
  # Reset any prior window first so re-lending is idempotent.
  sudo launchctl bootout "system/${AK_SUDO_LABEL}" 2> /dev/null
  if ! __ak.sudo.macos.renderPlist "${deadline}" "$(id -un)" | sudo tee "${AK_SUDO_PLIST}" > /dev/null; then
    return 1
  fi
  sudo chown 0:0 "${AK_SUDO_PLIST}"      # root:wheel — launchd refuses non-root-owned daemons
  sudo chmod 0644 "${AK_SUDO_PLIST}"
  sudo launchctl bootstrap system "${AK_SUDO_PLIST}"
}

# Cancel + clean up the auto-revoke facility. Idempotent; never fails the caller.
# Callers MUST run this while the grant is still in place: every step needs
# passwordless sudo, which is exactly what removing the drop-in takes away.
function __ak.sudo.timer.cancel() {
  if ak.os.type.isLinux; then
    # `stop`/`reset-failed` also cover a leftover TRANSIENT unit armed by a
    # pre-00c ankor-shell, which has no unit files to remove.
    sudo systemctl stop "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
    sudo systemctl disable --quiet "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
    sudo systemctl reset-failed "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
    sudo rm -f "${AK_SUDO_TIMER_PATH}" "${AK_SUDO_SERVICE_PATH}" "${AK_SUDO_HELPER}" \
      "${AK_SUDO_TIMER_WANTS}" "${AK_SUDO_SERVICE_WANTS}" "${AK_SUDO_TIMER_STAMP}" 2> /dev/null
    sudo systemctl daemon-reload 2> /dev/null
    return 0
  fi
  sudo launchctl bootout "system/${AK_SUDO_LABEL}" 2> /dev/null
  sudo rm -f "${AK_SUDO_PLIST}"
  return 0
}

# Echo an epoch as wall-clock `HH:MM <TZ>` in the LOCAL zone of whoever calls it.
# The zone label is not decoration: ak.sudo.remote-status renders on the remote
# host (often UTC) while ak.sudo.remote-status-all renders the same deadline on
# the operator's machine — without %Z the two outputs silently disagree.
# BSD date takes an epoch via `-r`, GNU via `-d @…`; try BSD first since GNU's
# `-r` means "reference FILE" and simply fails here. Best-effort: prints nothing
# if neither works, and callers treat that as "no clock".
function __ak.sudo.epochClock() {
  date -r "$1" '+%H:%M %Z' 2> /dev/null || date -d "@$1" '+%H:%M %Z' 2> /dev/null
}

# Echo "<Xm Ys> left (until HH:MM TZ)" for a deadline epoch — the single wording
# used by every status output, local and remote. Nothing when the deadline is
# unknown or already past.
# @param $1 deadline epoch seconds
function __ak.sudo.formatRemaining() {
  local -r dl="${1:-}"
  [[ "${dl}" =~ ^[0-9]+$ ]] || return 0

  local -r now="$(date +%s)"
  (( dl > now )) || return 0

  local -r left=$(( dl - now ))
  local -r clock="$(__ak.sudo.epochClock "${dl}")"
  printf '%dm %ds left%s' "$(( left / 60 ))" "$(( left % 60 ))" "${clock:+ (until ${clock})}"
}

# Echo the auto-revoke deadline as epoch seconds, or nothing when unknown.
# Epoch (not "minutes left") so a remote consumer renders the absolute time in
# ITS OWN timezone. Reading the drop-in needs passwordless sudo — which is
# guaranteed exactly when there IS an active grant to report on.
function __ak.sudo.timer.deadlineEpoch() {
  local dl=''
  dl="$(sudo -n grep -oE '^# AKDL=[0-9]+' "${AK_SUDO_FILE}" 2> /dev/null | head -n1 | cut -d= -f2)"
  if [[ -n "${dl}" ]]; then
    printf '%s\n' "${dl}"
    return 0
  fi

  # Fallback for a grant lent by an older version (no AKDL comment yet): macOS
  # bakes the same epoch into the world-readable plist. On Linux there is no such
  # fallback — that grant simply reports no countdown until the next lend.
  ak.os.type.isMacOS || return 0
  [[ -f "${AK_SUDO_PLIST}" ]] || return 0
  grep -oE 'AKDL=[0-9]+' "${AK_SUDO_PLIST}" 2> /dev/null | head -n1 | cut -d= -f2
  return 0
}

# Echo a human " — <time> left (until …)" suffix for status, or nothing when unknown.
function __ak.sudo.timer.remaining() {
  # Explicit initializers: zsh without TYPESET_SILENT prints `name=value` for a
  # bare `local name` whose parameter exists in an enclosing scope — that noise
  # would pollute this function's stdout.
  local remaining=''
  remaining="$(__ak.sudo.formatRemaining "$(__ak.sudo.timer.deadlineEpoch)")"
  [[ -n "${remaining}" ]] && printf ' — %s' "${remaining}"
  return 0
}

# Map sudo's stderr after a failed `sudo -S -v` (rendered under LC_ALL=C, so
# the wording is stable) to an AK_SUDO_RC_* code; 1 when nothing matches.
# Pure — no side effects.
# @param $1 sudo's stderr
# @output the exit code
function __ak.sudo.classifyAuthError() {
  local -r err="${1:-}"
  local -r badPasswordRe='incorrect password|Sorry, try again'
  local -r needsTtyRe='a terminal is required|must have a tty|requiretty'

  if [[ "${err}" =~ ${badPasswordRe} ]]; then
    printf '%s\n' "${AK_SUDO_RC_BAD_PASSWORD}"
    return 0
  fi
  if [[ "${err}" =~ ${needsTtyRe} ]]; then
    printf '%s\n' "${AK_SUDO_RC_NEEDS_TTY}"
    return 0
  fi
  printf '1\n'
}

# Authenticate sudo with the password waiting on <fd> — without a tty.
# Returns 0 — sudo now runs on OUR fresh credential cache;
#         __AK_SUDO_AUTH_VIA_GRANT — sudo is passwordless, but only thanks to
#           a live grant/rule (no password given, or it was rejected here);
#         an AK_SUDO_RC_* code / 1 — sudo is not usable.
# Prints `lend_auth=rejected` to stdout when the password was rejected but a
# live grant kept sudo passwordless, so the calling side can say so.
#
# sudo runs as a DIRECT child of the calling shell, on purpose: without a tty
# its credential cache is keyed to the PARENT pid, and the `sudo tee` that
# writes the drop-in (also a direct child) must find that cache. Inside `$( … )`
# sudo's parent would be a throwaway subshell — hence this function must never
# be called from a command substitution, and sudo's stderr goes to a temp file
# (the password never does: it travels through a pipe only).
# @param $1 fd  the descriptor to read ONE line (the password) from
function __ak.sudo.authenticateFromFd() {
  # xtrace would print the password — off for this function only.
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt localoptions noxtrace
  else
    local -
    set +x
  fi

  local -r fd="$1"
  if ! { true <&"${fd}"; } 2> /dev/null; then
    ak.sh.err "ak.sudo.lend: --password-fd ${fd} is not open."
    return 1
  fi

  # An empty pipe yields an empty line (read returns 1 at EOF) — that is the
  # "no password" case, not an error.
  local pw=''
  IFS= read -r -u "${fd}" pw

  if [[ -z "${pw}" ]]; then
    unset pw
    __ak.sudo.passwordless && return "${__AK_SUDO_AUTH_VIA_GRANT}"
    ak.sh.err "ak.sudo.lend: no password on fd ${fd}, and sudo is not passwordless here."
    return "${AK_SUDO_RC_NO_PASSWORD}"
  fi

  local errFile=''
  errFile="$(mktemp "${TMPDIR:-/tmp}/ak-sudo-auth.XXXXXX" 2> /dev/null)"
  [[ -z "${errFile}" ]] && ak.sh.warn "ak.sudo.lend: mktemp failed — sudo's own error message will not be shown."

  # Even when the host is passwordless right now: a grant may vanish mid-lend,
  # a fresh cache cannot. `printf` is a builtin — the password never reaches argv.
  printf '%s\n' "${pw}" | LC_ALL=C sudo -S -p '' -v > /dev/null 2> "${errFile:-/dev/null}"
  local -r authRc=$?
  unset pw

  local err=''
  if [[ -n "${errFile}" ]]; then
    err="$(cat "${errFile}" 2> /dev/null)"
    rm -f "${errFile}"
  fi

  if (( authRc == 0 )); then
    __ak.sudo.passwordless && return 0
    ak.sh.err "ak.sudo.lend: password accepted, but the sudo credential cache is not reusable here — timestamp_timeout=0 / timestamp_type in sudoers?"
    return "${AK_SUDO_RC_NO_CACHE}"
  fi

  if __ak.sudo.passwordless; then
    ak.sh.warn "ak.sudo.lend: sudo rejected the password here, but a live grant keeps sudo passwordless — re-lending on it."
    printf 'lend_auth=rejected\n'
    return "${__AK_SUDO_AUTH_VIA_GRANT}"
  fi

  [[ -n "${err}" ]] && ak.sh.err "sudo: ${err}"
  return "$(__ak.sudo.classifyAuthError "${err}")"
}

# `ak.sudo.lend --password-fd <n> [minutes]` — the non-interactive lend behind
# ak.sudo.remote-lend-many: the password arrives as ONE line on fd <n> (empty
# line / EOF = none given), sudo reads it via `-S` with no tty involved, then
# the regular lend runs on the fresh credential cache.
# Returns 0, the lend's own code, or an AK_SUDO_RC_* code.
# @param $1 fd      3..9
# @param $2 minutes optional, default AK_SUDO_DEFAULT_MINUTES
function __ak.sudo.lendWithPasswordFd() {
  local -r fd="${1:-}"
  local -r mins="${2:-${AK_SUDO_DEFAULT_MINUTES}}"
  local -r usage="Usage: ak.sudo.lend --password-fd <${AK_SUDO_PASSWORD_FD_MIN}..${AK_SUDO_PASSWORD_FD_MAX}> [minutes 1..1440]"

  if (( $# < 1 || $# > 2 )) || [[ ! "${fd}" =~ ^[0-9]$ ]] \
    || (( fd < AK_SUDO_PASSWORD_FD_MIN || fd > AK_SUDO_PASSWORD_FD_MAX )); then
    ak.sh.err "${usage}"
    return 1
  fi
  if ! __ak.sudo.validMinutes "${mins}"; then
    ak.sh.err "${usage}"
    return 1
  fi

  # NOT in `$( … )` — see __ak.sudo.authenticateFromFd for why.
  __ak.sudo.authenticateFromFd "${fd}"
  local -r authRc=$?
  local onOwnCache=1
  if (( authRc == __AK_SUDO_AUTH_VIA_GRANT )); then
    onOwnCache=0
  elif (( authRc != 0 )); then
    return "${authRc}"
  fi

  ak.sudo.lend "${mins}"
  local -r lendRc=$?
  (( lendRc == 0 )) && return 0

  # A lend that ran on a live grant fails when that grant vanishes mid-lend
  # (expired / revoked elsewhere) — say so with a distinct code, the caller
  # retries with a password. On our own cache the failure is real: fail-closed
  # reverts end with `sudo -k`, which must not read as a vanished grant.
  if (( ! onOwnCache )) && ! __ak.sudo.passwordless; then
    ak.sh.err "ak.sudo.lend: the grant vanished during the lend — a sudo password is needed."
    return "${AK_SUDO_RC_NO_PASSWORD}"
  fi
  return "${lendRc}"
}

##
# Grant passwordless sudo to the current user for N minutes (default
# AK_SUDO_DEFAULT_MINUTES = 30, range 1..1440).
# Prompts for your password ONCE (the first sudo). Auto-revokes via a reboot-safe
# job (systemd units on Linux, a LaunchDaemon on macOS); re-running MOVES the
# window (the message says so explicitly).
#
# Fails CLOSED: if the auto-revoke cannot be armed, the grant is reverted rather
# than left unenforced — including a still-valid grant this call was re-lending.
# An unenforced grant is precisely the failure this module exists to prevent.
#
# `--password-fd <n>` (n = 3..9): non-interactive mode for
# ak.sudo.remote-lend-many — the password comes as one line on fd <n>, never
# from a tty. Exit codes AK_SUDO_RC_* (see the top of this file) tell the caller
# why it failed.
# @param $1 minutes (optional, default AK_SUDO_DEFAULT_MINUTES)
#
# @example
#   ak.sudo.lend 20
#   printf '%s\n' "${pw}" | ak.sudo.lend --password-fd 3 20 3<&0
##
function ak.sudo.lend() {
  __ak.sudo.preflight || return 1

  if [[ "${1:-}" == '--password-fd' ]]; then
    shift
    __ak.sudo.lendWithPasswordFd "$@"
    return
  fi

  # Catch the collapsed-quoting remote invocation BEFORE applying the default:
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
    ak.sh.err "Usage: ak.sudo.lend [minutes 1..1440]  (default ${AK_SUDO_DEFAULT_MINUTES}) — got $# arguments"
    return 1
  fi

  local -r mins="${1:-${AK_SUDO_DEFAULT_MINUTES}}"
  if ! __ak.sudo.validMinutes "${mins}"; then
    ak.sh.err "Usage: ak.sudo.lend [minutes 1..1440]  (default ${AK_SUDO_DEFAULT_MINUTES})"
    return 1
  fi

  local -r user="$(id -un)"
  local -r line="${user} ALL=(ALL) NOPASSWD: ALL"

  # Read the CURRENT window BEFORE the drop-in is overwritten: re-lending MOVES
  # the deadline, and announcing the move is what stops an operator from counting
  # the window from the FIRST lend (a 30m grant re-lent at minute 25 ends at
  # minute 55 — correct, but indistinguishable from a stuck timer if unsaid).
  local wasGranted=0
  local prevDeadline=''
  if __ak.sudo.granted; then
    wasGranted=1
    prevDeadline="$(__ak.sudo.timer.deadlineEpoch)"
  elif __ak.sudo.hasStandingNopasswdRule; then
    # Heads-up: if a STANDING NOPASSWD rule (NOT ak's) already grants passwordless
    # sudo, lending is cosmetic — ak.sudo.revoke / the auto-revoke only remove ak's
    # file, never that rule. A lingering credential cache is NOT a rule, so we
    # probe the policy via `sudo -l`, not `sudo -n true`.
    ak.sh.warn "passwordless sudo is ALREADY available via a standing sudoers rule (not ak) — ak.sudo.revoke / auto-revoke will NOT remove it."
  fi

  local -r deadlineEpoch="$(( $(date +%s) + mins * 60 ))"
  local -r deadlineClock="$(__ak.sudo.epochClock "${deadlineEpoch}")"

  # Write + validate the drop-in (revert if it would break sudo). The deadline
  # goes in with it, as an inert comment, in ONE write: `visudo -cf` then checks
  # the exact bytes sudo will re-parse, and the grant never exists on disk
  # without the deadline the auto-revoke reads back. Shape is fixed and verified
  # — "# AKDL=<digits>", a comment, never sudo's `#uid` form, which has no space.
  # The drop-in is also the only home the deadline needs: it dies with the grant
  # it describes, so there is nothing extra to clean up.
  # Use `tee` then chmod/chown — `install /dev/stdin` is flaky with uutils-coreutils
  # (Ubuntu 26.04) over a non-tty session ("install: No such file or directory").
  if ! printf '%s\n# AKDL=%s\n' "${line}" "${deadlineEpoch}" | sudo tee "${AK_SUDO_FILE}" > /dev/null; then
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

  # (Re)arm the auto-revoke safety net. Idempotent: re-running MOVES the window.
  __ak.sudo.timer.arm "${deadlineEpoch}"
  case "$?" in
    0)
      if (( wasGranted )); then
        local -r prevClock="$(__ak.sudo.epochClock "${prevDeadline}")"
        ak.sh.ok "passwordless sudo RE-lent to '${user}' for ${mins}m — window moved${prevClock:+ from ${prevClock}}${deadlineClock:+ to ${deadlineClock}}" "SUDO"
      else
        ak.sh.ok "passwordless sudo lent to '${user}' for ${mins}m${deadlineClock:+ (until ${deadlineClock})} — auto-revokes, or run ak.sudo.revoke" "SUDO"
      fi
      ;;
    2)
      ak.sh.warn "no auto-revoke facility available: NO auto-revoke scheduled — you MUST run ak.sudo.revoke!"
      ak.sh.ok "passwordless sudo lent to '${user}' (manual revoke required)" "SUDO"
      ;;
    *)
      # Fail CLOSED. A warning printed into the middle of an `ssh -t` session is
      # not a safety net; an unenforced root grant left behind is a hole. Cancel
      # BEFORE removing the drop-in — every step below still needs the very
      # passwordless sudo that removal takes away.
      __ak.sudo.timer.cancel
      sudo rm -f "${AK_SUDO_FILE}"
      if __ak.sudo.granted; then
        ak.sh.err "ak.sudo.lend: auto-revoke could not be armed AND ${AK_SUDO_FILE} could not be removed — delete it manually NOW."
        return 1
      fi
      sudo -k
      ak.sh.err "ak.sudo.lend: auto-revoke could not be armed — the grant was reverted (fail closed), sudo asks for a password again."
      return 1
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
#           of prose: `granted=1 deadline_epoch=<epoch> lend_api=1` (epoch
#           omitted when unknown) or `granted=0 lend_api=1`. Consumed by
#           ak.sudo.remote-status-all and ak.sudo.remote-lend-many over SSH —
#           keep the format stable. Fields are space-separated `key=value`;
#           `granted=` always comes first. Only APPEND new fields: parsers
#           must ignore fields they do not know.
#           `lend_api=1` — capability marker: this host's ak.sudo.lend
#           supports `--password-fd` (needed by ak.sudo.remote-lend-many).
##
function ak.sudo.status() {
  __ak.sudo.preflight || return 1

  if [[ "${1:-}" == '--porcelain' ]]; then
    if __ak.sudo.granted; then
      local -r dl="$(__ak.sudo.timer.deadlineEpoch)"
      printf 'granted=1%s lend_api=1\n' "${dl:+ deadline_epoch=${dl}}"
    else
      printf 'granted=0 lend_api=1\n'
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
