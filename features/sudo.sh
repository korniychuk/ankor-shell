#!/usr/bin/env bash

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

# True if sudo currently runs WITHOUT a password — for ANY reason: an ak grant,
# a cached credential timestamp, OR a standing NOPASSWD rule we don't manage.
# Never prompts (`-n`).
function __ak.sudo.passwordless() {
  sudo -n true 2> /dev/null
}

# True if OUR temp drop-in is present — the single source of truth for an ak
# grant. Statting it needs passwordless sudo (the dir is root:root 0750); if sudo
# would prompt, there cannot be an active passwordless ak grant anyway, so a
# silent failure correctly reads as "absent".
function __ak.sudo.granted() {
  sudo -n test -f "${AK_SUDO_FILE}" 2> /dev/null
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

  sudo systemctl stop "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
  sudo systemctl reset-failed "${AK_SUDO_UNIT}.timer" "${AK_SUDO_UNIT}.service" 2> /dev/null
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
  local remaining=""

  # systemctl status renders: "Trigger: <date>; 23min 14s left"
  local timer_status trigger_re
  timer_status="$(systemctl status "${AK_SUDO_UNIT}.timer" 2>/dev/null)"
  trigger_re='Trigger:[^;]+;[[:space:]]*(.+left)'
  if [[ "${timer_status}" =~ ${trigger_re} ]]; then
    remaining=" — ${BASH_REMATCH[1]}"
  fi

  ak.sh.ok "passwordless sudo available for '${user}'${remaining}" "ACTIVE"
}
