#!/usr/bin/env bash

#
# Simple HTTP Server for static files
#
# Examples:
#
#   ak.inet.serve                    # server on 127.0.0.1:8000
#   ak.inet.serve 9000 192.168.1.2   # server on 192.168.0.1:9000
#
# Dependencies:
#   - Python 3
#
function ak.inet.serve() {
  local -r -i port="${1:-8000}"
  local -r ip="${2:-127.0.0.1}"

  if ! ak.bash.commandExists python3; then
    echo "ERROR! python3 interpreter not found" >&2
    return 1
  fi

  echo "Press Ctrl + C to stop the server.\n"
  python3 -m http.server ${port} --bind "${ip}"
}

#
# Show listening on the local machine ports and PIDs of processes
# TODO: implement the way to run without sudo
#
# The code is taken from this link:
# https://stackoverflow.com/questions/4421633/who-is-listening-on-a-given-tcp-port-on-mac-os-x
#
function ak.inet.showListeningPorts() {
    if [[ ${#} -eq 0 ]]; then
        sudo lsof -iTCP -sTCP:LISTEN -n -P
    elif [[ ${#} -eq 1 ]]; then
        sudo lsof -iTCP -sTCP:LISTEN -n -P | grep -i --color $1
    else
        echo "Usage: listening [pattern]"
    fi
}

function ak.inet.IPsOfHost() {
  local -r hostName="$1"; shift

  dig +short "${hostName}"
}

function ak.inet.firstIPOfHost() {
  local -r hostName="$1"; shift

  ak.inet.IPsOfHost "${hostName}" | awk '{ print ; exit }'
}

function ak.inet.ping.IPv4() {
  ping 8.8.8.8
}

function ak.inet.ping.DNS() {
  ping google.com
}

#
# Retrieves external(public) IPv4 using dig utility.
# You can use the function to check VPN or Proxy privacy.
#
# Notice: DNS can work around your VPN
#
function ak.inet.getExternalIPv4() {
  dig @resolver1.opendns.com A myip.opendns.com +short -4
}

#
# Retrieves external(public) IPv6 using dig utility.
# You can use the function to check VPN or Proxy privacy.
#
# Notice: DNS can work around your VPN
#
function ak.inet.getExternalIPv6() {
  dig @resolver1.opendns.com AAAA myip.opendns.com +short -6
}

#
# Helpful links:
# https://unix.stackexchange.com/questions/190513/shell-scripting-proper-way-to-check-for-internet-connectivity
# https://stackoverflow.com/questions/5195607/checking-bash-exit-status-of-several-commands-efficiently
#
function ak.inet.check() {
  echo "Internet connection checking ..."
  local -i noInet=0

  if ! __ak.inet.check.IPv4; then
    echo "[Fail] IPv4"
    noInet=1
  else
    echo "[OK] IPv4"
  fi

  if ! __ak.inet.check.DNS; then
    echo "[Fail] DNS"
    noInet=1
  else
    echo "[OK] DNS"
  fi

  __ak.inet.check.connectivity
  local -r errCode="$?"
  if [[ ${errCode} -ne 0 ]]; then
    echo -n "[Fail] Connectivity"
    case "${errCode}" in
         1) echo " (The web proxy won't let us through)";;
         2) echo " (The network is down or very slow)";;
         *) echo " (Unknown error)";;
    esac
    noInet=1
  else
    echo "[OK] Connectivity"
  fi

  return ${noInet}
}

function __ak.inet.check.IPv4() {
  ping -q -c 1 -W 1 8.8.8.8 >/dev/null 2>/dev/null
  return $?
}

# TODO: add timeout. The method is too slow
function __ak.inet.check.DNS() {
  ping -q -c 1 -W 1 google.com >/dev/null 2>/dev/null
  return $?
}

function __ak.inet.check.connectivity() {
  case "$(curl -s --max-time 2 -I http://google.com | sed 's/^[^ ]*  *\([0-9]\).*/\1/; 1q')" in
    [23]) return 0;; # HTTP connectivity is up
       5) return 1;; # The web proxy won't let us through
       *) return 2;; # The network is down or very slow
  esac
}
