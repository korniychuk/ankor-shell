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
# One-shot from another machine (function lives in an interactive rc):
#   ssh -t HOST 'bash -lic "ak.sudo.lend 60"'
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

# Echo a human " — <time> left" suffix for status, or nothing when unknown.
function __ak.sudo.timer.remaining() {
  if ak.os.type.isLinux; then
    # systemctl status renders: "Trigger: <date>; 23min 14s left"
    local timer_status trigger_re
    timer_status="$(systemctl status "${AK_SUDO_UNIT}.timer" 2> /dev/null)"
    trigger_re='Trigger:[^;]+;[[:space:]]*(.+left)'
    [[ "${timer_status}" =~ ${trigger_re} ]] && printf ' — %s' "${BASH_REMATCH[1]}"
    return 0
  fi

  # macOS: recover the deadline epoch baked into the (world-readable) plist.
  [[ -f "${AK_SUDO_PLIST}" ]] || return 0
  local dl now left
  dl="$(grep -oE 'AKDL=[0-9]+' "${AK_SUDO_PLIST}" 2> /dev/null | head -n1 | cut -d= -f2)"
  [[ -n "${dl}" ]] || return 0
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

  local -r mins="${1:-30}"
  if [[ ! "${mins}" =~ ^[0-9]+$ ]] || (( mins < 1 || mins > 1440 )); then
    ak.sh.err "Usage: ak.sudo.lend [minutes 1..1440]  (default 30)"
    return 1
  fi

  local -r user="$(id -un)"
  local -r line="${user} ALL=(ALL) NOPASSWD: ALL"

  # Heads-up: if sudo is ALREADY passwordless before we lend (and it isn't our own
  # prior grant), a STANDING rule grants it permanently. Lending is then cosmetic —
  # ak.sudo.revoke / the auto-revoke timer only remove ak's file, never that rule.
  if ! __ak.sudo.granted && __ak.sudo.passwordless; then
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
  __ak.sudo.timer.arm "${mins}"
  case "$?" in
    0)
      ak.sh.ok "passwordless sudo lent to '${user}' for ${mins}m — auto-revokes, or run ak.sudo.revoke" "SUDO"
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
    if __ak.sudo.passwordless; then
      ak.sh.warn "but passwordless sudo IS still available via a rule NOT managed by ak.sudo (e.g. another /etc/sudoers.d/* file) — revoke cannot remove that."
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
##
function ak.sudo.status() {
  __ak.sudo.preflight || return 1

  # The grant IS the sudoers drop-in — check the file, not just `sudo -n true`,
  # which can also succeed purely from sudo's cached credential timestamp or a
  # standing NOPASSWD rule.
  if ! __ak.sudo.granted; then
    if __ak.sudo.passwordless; then
      ak.sh.warn "no ak grant — but passwordless sudo IS available via another sudoers rule (not managed by ak.sudo)."
    else
      echo "inactive — no active grant (sudoers drop-in not present)"
    fi
    return 0
  fi

  local -r user="$(id -un)"
  local -r remaining="$(__ak.sudo.timer.remaining)"

  ak.sh.ok "passwordless sudo available for '${user}'${remaining}" "ACTIVE"
}
