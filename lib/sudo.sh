#!/usr/bin/env bash

# TODO: move to /features/sudo.sh

##
# ak.sudo.* — lend the CURRENT user temporary passwordless sudo, time-boxed with
# an automatic revoke (systemd timer) as a safety net. Linux + sudo + systemd.
#
# Purpose: let an automation/agent (or a quick maintenance window) run privileged
# commands for a BOUNDED time WITHOUT ever sharing your password. You run
# `ak.sudo.lend` once (typing your password a single time); a transient systemd
# timer auto-revokes the grant after N minutes, or call `ak.sudo.revoke`.
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
declare -r AK_SUDO_UNIT="ak-sudo-revoke"

function __ak.sudo.preflight() {
  if ! ak.os.type.isLinux; then
    ak.sh.err "ak.sudo.* is Linux-only (needs /etc/sudoers.d + systemd)."
    return 1
  fi
  if ! ak.sh.commandExists sudo; then
    ak.sh.err "ak.sudo.*: 'sudo' not found."
    return 1
  fi
  return 0
}

##
# Grant passwordless sudo to the current user for N minutes (default 30, range 1..1440).
# Prompts for your password ONCE (the first sudo). Auto-revokes via a transient
# systemd timer; re-running re-arms the window.
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

  # Write + validate the drop-in (revert if it would break sudo).
  # Use `tee` then chmod/chown — `install /dev/stdin` is flaky with uutils-coreutils
  # (Ubuntu 26.04) over a non-tty session ("install: No such file or directory").
  if ! printf '%s\n' "${line}" | sudo tee "${AK_SUDO_FILE}" > /dev/null; then
    ak.sh.err "ak.sudo.lend: failed to write ${AK_SUDO_FILE}"
    return 1
  fi
  sudo chown root:root "${AK_SUDO_FILE}"
  sudo chmod 0440 "${AK_SUDO_FILE}"
  if ! sudo visudo -cf "${AK_SUDO_FILE}" > /dev/null; then
    sudo rm -f "${AK_SUDO_FILE}"
    ak.sh.err "ak.sudo.lend: sudoers validation failed — reverted, no change."
    return 1
  fi

  # (Re)arm the auto-revoke timer. Idempotent: fully clear any prior transient unit
  # (timer + service) first, so calling ak.sudo.lend several times in a row just
  # RESETS the window instead of failing on "Unit already exists".
  sudo systemctl stop "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
  sudo systemctl reset-failed "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
  if ak.sh.commandExists systemd-run; then
    if sudo systemd-run --quiet --unit="${AK_SUDO_UNIT}" --on-active="${mins}min" \
         /bin/rm -f "${AK_SUDO_FILE}"; then
      ak.sh.ok "passwordless sudo lent to '${user}' for ${mins}m — auto-revokes, or run ak.sudo.revoke" "SUDO"
    else
      ak.sh.warn "grant active but auto-revoke timer failed to arm — run ak.sudo.revoke when done!"
    fi
  else
    ak.sh.warn "systemd-run unavailable: NO auto-revoke scheduled — you MUST run ak.sudo.revoke!"
    ak.sh.ok "passwordless sudo lent to '${user}' (manual revoke required)" "SUDO"
  fi
}

##
# Revoke the temporary passwordless sudo immediately and cancel the auto-revoke timer.
##
function ak.sudo.revoke() {
  __ak.sudo.preflight || return 1

  # No-op notice: if passwordless sudo isn't currently available there is no active
  # grant to revoke (already revoked, or auto-expired). Bail out BEFORE touching sudo
  # so an idle call never prompts for a password.
  if ! sudo -n true 2> /dev/null; then
    echo "ak.sudo.revoke: nothing to revoke — no active grant (already revoked or auto-expired)."
    return 0
  fi

  sudo systemctl stop "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
  sudo systemctl reset-failed "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
  sudo rm -f "${AK_SUDO_FILE}"

  if sudo -n test -f "${AK_SUDO_FILE}" 2> /dev/null; then
    ak.sh.err "ak.sudo.revoke: ${AK_SUDO_FILE} still present — remove it manually."
    return 1
  fi
  ak.sh.ok "temporary passwordless sudo revoked" "SUDO"
}

##
# Report whether the temporary grant is active and when it auto-revokes.
##
function ak.sudo.status() {
  __ak.sudo.preflight || return 1

  if sudo -n true 2> /dev/null; then
    ak.sh.ok "passwordless sudo currently available for '$(id -un)'" "ACTIVE"
    systemctl list-timers "${AK_SUDO_UNIT}.timer" --all --no-pager 2> /dev/null | sed -n '1,2p'
  else
    echo "inactive — sudo requires a password (no active grant)"
  fi
}
