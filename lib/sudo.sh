#!/usr/bin/env bash

##
# ak.sudo.* — lend the CURRENT user temporary passwordless sudo, time-boxed with
# an automatic revoke (systemd timer) as a safety net. Linux + sudo + systemd.
#
# Purpose: let an automation/agent (or a quick maintenance window) run privileged
# commands for a BOUNDED time WITHOUT ever sharing your password. You run
# `ak.sudo.lend` once (typing your password a single time); a transient systemd
# timer auto-revokes the grant after N minutes, or call `ak.sudo.return`.
#
# @example
#   ak.sudo.lend            # grant for 30 min (default)
#   ak.sudo.lend 120        # grant for 2 hours
#   ak.sudo.status          # is it active? when does it auto-revoke?
#   ak.sudo.return          # revoke now + cancel the timer
#
# One-shot from another machine (function lives in an interactive rc):
#   ssh -t HOST 'bash -lic "ak.sudo.lend 60"'
##

declare -r AK_SUDO_FILE="/etc/sudoers.d/99-ak-temp-sudo"
declare -r AK_SUDO_UNIT="ak-sudo-revoke"

function __ak.sudo.preflight() {
  if ! ak.os.type.isLinux; then
    echo "ak.sudo.* is Linux-only (needs /etc/sudoers.d + systemd)." >&2
    return 1
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    echo "ak.sudo.*: 'sudo' not found." >&2
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
    echo "Usage: ak.sudo.lend [minutes 1..1440]  (default 30)" >&2
    return 1
  fi

  local -r user="$(id -un)"
  local -r line="${user} ALL=(ALL) NOPASSWD: ALL"

  # Write + validate the drop-in (revert if it would break sudo).
  if ! printf '%s\n' "${line}" | sudo install -m 0440 -o root -g root /dev/stdin "${AK_SUDO_FILE}"; then
    echo "ak.sudo.lend: failed to write ${AK_SUDO_FILE}" >&2
    return 1
  fi
  if ! sudo visudo -cf "${AK_SUDO_FILE}" >/dev/null; then
    sudo rm -f "${AK_SUDO_FILE}"
    echo "ak.sudo.lend: sudoers validation failed — reverted, no change." >&2
    return 1
  fi

  # (Re)arm the auto-revoke timer.
  sudo systemctl stop "${AK_SUDO_UNIT}.timer" 2>/dev/null
  sudo systemctl reset-failed "${AK_SUDO_UNIT}.service" 2>/dev/null
  if command -v systemd-run >/dev/null 2>&1; then
    if sudo systemd-run --quiet --unit="${AK_SUDO_UNIT}" --on-active="${mins}min" \
         /bin/rm -f "${AK_SUDO_FILE}"; then
      echo "✅ passwordless sudo lent to '${user}' for ${mins}m — auto-revokes, or run ak.sudo.return"
    else
      echo "⚠️  grant active but auto-revoke timer failed to arm — run ak.sudo.return when done!" >&2
    fi
  else
    echo "⚠️  systemd-run unavailable: NO auto-revoke scheduled — you MUST run ak.sudo.return!" >&2
    echo "✅ passwordless sudo lent to '${user}' (manual revoke required)"
  fi
}

##
# Revoke the temporary passwordless sudo immediately and cancel the auto-revoke timer.
##
function ak.sudo.return() {
  __ak.sudo.preflight || return 1

  sudo systemctl stop "${AK_SUDO_UNIT}.timer" 2>/dev/null
  sudo systemctl reset-failed "${AK_SUDO_UNIT}.service" 2>/dev/null
  sudo rm -f "${AK_SUDO_FILE}"

  if sudo -n test -f "${AK_SUDO_FILE}" 2>/dev/null; then
    echo "ak.sudo.return: ${AK_SUDO_FILE} still present — remove it manually." >&2
    return 1
  fi
  echo "✅ temporary passwordless sudo revoked"
}

##
# Report whether the temporary grant is active and when it auto-revokes.
##
function ak.sudo.status() {
  __ak.sudo.preflight || return 1

  if sudo -n true 2>/dev/null; then
    echo "ACTIVE — passwordless sudo currently available for '$(id -un)'"
    systemctl list-timers "${AK_SUDO_UNIT}.timer" --all --no-pager 2>/dev/null | sed -n '1,2p'
  else
    echo "inactive — sudo requires a password (no active grant)"
  fi
}
