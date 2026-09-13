#!/usr/bin/env bash
# Diagnostic helpers run inside ak.inet.check and inherit its subshell locals.
# shellcheck disable=SC2030,SC2031

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

  if ! ak.sh.commandExists python3; then
    echo "ERROR! python3 interpreter not found" >&2
    return 1
  fi

  echo "Press Ctrl + C to stop the server.\n"
  python3 -m http.server ${port} --bind "${ip}"
}

##
 # Show listening on the local machine TCP ports and PIDs of processes
 # TODO: implement the way to run without sudo
 #
 # @param {integer} [port=] Port number, if you want to find only one specific application
 #
 # @example <caption>Show all allocated ports</caption>
 #
 #   $ ak.inet.showListeningPorts
 #
 #   > docker-pr 12497 root    4u  IPv6 57034858      0t0  TCP *:443 (LISTEN)
 #   > docker-pr 12509 root    4u  IPv6 57034885      0t0  TCP *:80 (LISTEN)
 #   > ...
 #
 # @example <caption>Find the process that took port 80</caption>
 #
 #   $ ak.inet.showListeningPorts 80
 #
 #   > docker-pr 12509 root    4u  IPv6 57034885      0t0  TCP *:80 (LISTEN)
 #
 # The code is taken from this link:
 # https://stackoverflow.com/questions/4421633/who-is-listening-on-a-given-tcp-port-on-mac-os-x
##
function ak.inet.showListeningPorts() {
  local -r -i port="${1}"

  if [[ ${#} -eq 0 ]]; then
    sudo lsof -iTCP -sTCP:LISTEN -n -P
  elif [[ ${#} -eq 1 ]]; then
    sudo lsof -iTCP -sTCP:LISTEN -n -P | grep -i --color "${port}"
  else
    echo "Usage: listening [port]"
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

#
# Interactive ping: runs until `q` (or Ctrl+C) is pressed, so a wrapper that
# embeds it (e.g. a herdr tab) needs no extra "press any key" step afterwards.
# Falls back to plain foreground ping when stdin is not a terminal.
# Works under bash and zsh (the key read differs — see below).
#
function __ak.inet.ping.interactive() {
  local -r target="$1"; shift

  if [[ ! -t 0 ]]; then
    ping "${target}"
    return $?
  fi

  local pingPid key rc=0 quit=0
  ping "${target}" &
  pingPid=$!
  # Ctrl+C: stop ping, restore the handler, leave. `kill` may race a ping that
  # already died — that is fine, the error is ignored.
  trap 'kill "${pingPid}" 2>/dev/null; trap - INT; return 130' INT

  while kill -0 "${pingPid}" 2>/dev/null; do
    key=''
    if [[ -n "${ZSH_VERSION:-}" ]]; then
      read -rs -k1 -t 0.2 key 2>/dev/null || true
    else
      read -rs -n1 -t 0.2 key 2>/dev/null || true
    fi
    if [[ "${key}" == 'q' || "${key}" == 'Q' ]]; then
      kill "${pingPid}" 2>/dev/null
      quit=1
      break
    fi
  done
  trap - INT
  # `q` is a clean exit (0); a ping that died by itself (e.g. 68 = unknown host)
  # keeps its status, so callers can tell a failure from a deliberate quit.
  wait "${pingPid}" 2>/dev/null || rc=$?
  (( quit )) && return 0
  return "${rc}"
}

function ak.inet.ping.IPv4() {
  __ak.inet.ping.interactive 8.8.8.8
}

function ak.inet.ping.DNS() {
  __ak.inet.ping.interactive google.com
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

# Layered diagnostics. Workers own separate result files; only the parent prints.
# The main phase has a two-second deadline, followed by at most one second of DoH.
function ak.inet.check() (
  set +m
  if [[ -n "${ZSH_VERSION:-}" ]]; then unsetopt bgnice; fi
  local checkDir checkOS worker timer rc=1 key
  local -r phaseLimit=2 dohLimit=1
  echo 'Internet connection checking ...'
  if ! command -v perl >/dev/null; then
    echo "[Skip] Diagnostics: perl required for bounded process groups"
    return 1
  fi
  checkDir=$(mktemp -d "${TMPDIR:-/tmp}/ak-inet-check.XXXXXXXX") || {
    echo '[Fail] Diagnostics: cannot create temporary directory' >&2
    return 1
  }
  trap '__ak.inet.check.cleanup' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  __ak.inet.check.save route Info "unavailable (route lookup timeout)"
  checkOS=$(uname -s)
  for key in link router ping1 ping2 tcp1 tcp2 ipv6 system dns1 dns2; do
    printf 'Fail|timed out or unavailable\n' > "$checkDir/$key"
  done
  __ak.inet.check.runPhase "$phaseLimit" __ak.inet.check.launch
  if __ak.inet.check.is system Fail || __ak.inet.check.is dns1 Fail || __ak.inet.check.is dns2 Fail; then
    printf 'Fail|timed out or unavailable\n' > "$checkDir/doh"
    __ak.inet.check.runPhase "$dohLimit" __ak.inet.check.doh
  fi
  __ak.inet.check.print
  __ak.inet.check.verdict
  if { __ak.inet.check.is ping1 OK || __ak.inet.check.is ping2 OK ||
       __ak.inet.check.is tcp1 OK || __ak.inet.check.is tcp2 OK; } && __ak.inet.check.is system OK; then
    rc=0
  fi
  return "$rc"
)

# Each external probe gets its own process group, including any children it
# starts. Perl is already used by this module and ships with macOS; unlike
# ps/pgrep this also works inside sandboxes that prohibit process inspection.
function __ak.inet.check.run() (
  local commandPid commandRC=0
  [[ ! -f "$checkDir/deadline" ]] || return 124
  perl -e 'my $deadline=shift @ARGV; setpgrp(0,0) or die "setpgrp: $!"; exit 124 if -e $deadline; exec @ARGV or die "exec: $!"' -- "$checkDir/deadline" "$@" &
  commandPid=$!
  printf '%s\n' "$commandPid" > "$checkDir/pid.$commandPid"
  if [[ -f "$checkDir/deadline" ]]; then kill -TERM -- "-$commandPid" 2>/dev/null || true; fi
  wait "$commandPid" 2>/dev/null || commandRC=$?
  if kill -0 -- "-$commandPid" 2>/dev/null; then
    kill -TERM -- "-$commandPid" 2>/dev/null || true
    sleep 0.05
    kill -KILL -- "-$commandPid" 2>/dev/null || true
  fi
  rm -f "$checkDir/pid.$commandPid"
  return "$commandRC"
)

function __ak.inet.check.stopCommands() {
  local pidFile commandPid signalName
  : > "$checkDir/deadline"
  for signalName in TERM KILL; do
    while IFS= read -r pidFile; do
      { read -r commandPid < "$pidFile"; } 2>/dev/null || continue
      kill -"$signalName" -- "-$commandPid" 2>/dev/null || true
    done < <(find "$checkDir" -name 'pid.*')
    if [[ "$signalName" == TERM ]]; then sleep 0.05; fi
  done
}

function __ak.inet.check.cleanup() {
  __ak.inet.check.stopCommands
  if [[ -n "${timer:-}" ]]; then kill -TERM "$timer" 2>/dev/null || true; fi
  if [[ -n "${worker:-}" ]]; then wait "$worker" 2>/dev/null || true; fi
  wait 2>/dev/null || true
  rm -rf -- "$checkDir"
}

function __ak.inet.check.runPhase() {
  local limit=$1
  shift
  rm -f "$checkDir/deadline"
  ( "$@" ) &
  worker=$!
  (
    sleep "$limit" &
    local sleeper=$!
    trap 'kill "$sleeper" 2>/dev/null; wait "$sleeper" 2>/dev/null; exit 0' TERM
    wait "$sleeper"
    __ak.inet.check.stopCommands
  ) &
  timer=$!
  wait "$worker" 2>/dev/null || true
  kill -TERM "$timer" 2>/dev/null || true
  wait "$timer" 2>/dev/null || true
  worker='' timer=''
}

function __ak.inet.check.save() {
  printf '%s|%s\n' "$2" "${3:-}" > "$checkDir/$1"
}

function __ak.inet.check.is() {
  [[ -f "$checkDir/$1" ]] && [[ $(cut -d '|' -f1 "$checkDir/$1") == "$2" ]]
}

function __ak.inet.check.isTunnel() {
  case "$1" in utun*|tun*|wg*|tailscale*) return 0;; esac
  return 1
}

function __ak.inet.check.launch() {
  __ak.inet.check.topology &
  __ak.inet.check.ping ping1 1.1.1.1 &
  __ak.inet.check.ping ping2 8.8.8.8 &
  __ak.inet.check.tcp tcp1 1.1.1.1 &
  __ak.inet.check.tcp tcp2 8.8.8.8 &
  __ak.inet.check.ipv6 &
  __ak.inet.check.system &
  __ak.inet.check.dns dns1 1.1.1.1 &
  __ak.inet.check.dns dns2 8.8.8.8 &
  __ak.inet.check.proxy &
  __ak.inet.check.tailscale &
  wait
}

function __ak.inet.check.topology() {
  local primary gateway iface routes
  if [[ "$checkOS" == Darwin ]]; then
    routes=$(__ak.inet.check.run route -n get default 2>/dev/null)
    primary=$(printf '%s\n' "$routes" | awk '/interface:/{print $2; exit}')
    gateway=$(printf '%s\n' "$routes" | awk '/gateway:/{print $2; exit}')
  else
    routes=$(__ak.inet.check.run ip -4 route show default 2>/dev/null)
    primary=$(printf '%s\n' "$routes" | awk '{for(i=1;i<NF;i++) if($i=="dev") {print $(i+1); exit}}')
    gateway=$(printf '%s\n' "$routes" | awk '{for(i=1;i<NF;i++) if($i=="via") {print $(i+1); exit}}')
  fi
  iface=$primary
  __ak.inet.check.save route Info "${primary:-unavailable}"
  if __ak.inet.check.isTunnel "$primary"; then
    __ak.inet.check.save route Info "$primary (VPN tunnel)"
    printf '%s\n' "$primary" > "$checkDir/tunnel"
    if [[ "$checkOS" == Darwin ]]; then
      routes=$(__ak.inet.check.run netstat -rn -f inet 2>/dev/null | awk '$1=="default" && $3~/G/ && $3!~/I/ {for(i=4;i<=NF;i++) if($i~/^en[0-9]+$/) {print $2, $i; exit}}')
    else
      routes=$(printf '%s\n' "$routes" | awk '{g="";d="";for(i=1;i<NF;i++){if($i=="via")g=$(i+1);if($i=="dev")d=$(i+1)} if(d!~/^(tun|utun|wg|tailscale)/ && d!=""){print g,d;exit}}')
    fi
    gateway=${routes%% *}
    iface=${routes#* }
  fi
  __ak.inet.check.link "$iface"
  __ak.inet.check.ping router "$gateway" &
  if ! __ak.inet.check.isTunnel "$primary"; then __ak.inet.check.isp & fi
  wait
}

function __ak.inet.check.link() {
  local iface=$1 address
  if [[ -z "$iface" ]]; then
    __ak.inet.check.save link Fail 'no physical default interface'
    return
  fi
  if [[ "$checkOS" == Darwin ]]; then
    address=$(__ak.inet.check.run ifconfig "$iface" 2>/dev/null | awk '$1=="inet"{print $2;exit}')
  else
    address=$(__ak.inet.check.run ip -4 addr show dev "$iface" 2>/dev/null | awk '$1=="inet"{split($2,a,"/");print a[1];exit}')
  fi
  case "$address" in
    ''|169.254.*) __ak.inet.check.save link Fail "$iface ${address:-no IPv4 address}";;
    *) __ak.inet.check.save link OK "$iface $address";;
  esac
}

function __ak.inet.check.ping() {
  local key=$1 target=$2 output rtt
  if [[ -z "$target" ]]; then
    __ak.inet.check.save "$key" Fail 'no gateway'
    return
  fi
  if ! command -v ping >/dev/null; then
    __ak.inet.check.save "$key" Skip 'ping not installed'
    return
  fi
  if output=$(__ak.inet.check.run ping -n -c 1 "$target" 2>/dev/null); then
    rtt=$(printf '%s\n' "$output" | sed -nE 's/.*time([=<][[:space:]]*[0-9.]+).*/\1 ms/p' | head -1 | sed 's/^=//')
    __ak.inet.check.save "$key" OK "$target ${rtt:-RTT unavailable}"
  else
    __ak.inet.check.save "$key" Fail "$target no reply"
  fi
}

function __ak.inet.check.isp() {
  local hop
  command -v traceroute >/dev/null || return 0
  hop=$(__ak.inet.check.run traceroute -n -m 2 -q 1 -w 1 1.1.1.1 2>/dev/null | awk '$1==2 && $2~/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/{print $2;exit}')
  [[ -n "$hop" ]] || return 0
  __ak.inet.check.save isp Fail "$hop no reply (timeout)"
  __ak.inet.check.ping isp "$hop"
}

function __ak.inet.check.tcp() {
  local key=$1 target=$2 flag=-w
  if ! command -v nc >/dev/null; then
    __ak.inet.check.save "$key" Skip 'nc not installed'
    return
  fi
  if [[ "$checkOS" == Darwin ]]; then flag=-G; fi
  if __ak.inet.check.run nc -z "$flag" 1 "$target" 443 >/dev/null 2>&1; then
    __ak.inet.check.save "$key" OK
  else
    __ak.inet.check.save "$key" Fail 'connection failed'
  fi
}

function __ak.inet.check.ipv6() {
  local binary=ping cmd=(ping -6)
  if [[ "$checkOS" == Darwin ]]; then binary=ping6; cmd=(ping6); fi
  if ! command -v "$binary" >/dev/null; then
    __ak.inet.check.save ipv6 Skip 'IPv6 ping unavailable (info)'
    return
  fi
  if __ak.inet.check.run "${cmd[@]}" -n -c 1 2001:4860:4860::8888 >/dev/null 2>&1; then
    __ak.inet.check.save ipv6 OK '(info)'
  else
    __ak.inet.check.save ipv6 Fail 'no reply (info)'
  fi
}

function __ak.inet.check.system() {
  local output binary=getent cmd=(getent hosts google.com)
  if [[ "$checkOS" == Darwin ]]; then binary=dscacheutil; cmd=(dscacheutil -q host -a name google.com); fi
  if ! command -v "$binary" >/dev/null; then
    __ak.inet.check.save system Skip "$binary not installed"
    return
  fi
  if output=$(__ak.inet.check.run "${cmd[@]}" 2>/dev/null) &&
     printf '%s\n' "$output" | grep -Eq '(^|[[:space:]])([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|[0-9a-fA-F]*:[0-9a-fA-F:]+)'; then
    __ak.inet.check.save system OK
  else
    __ak.inet.check.save system Fail 'system resolver returned no address'
  fi
}

function __ak.inet.check.dns() {
  local output
  if ! command -v dig >/dev/null; then
    __ak.inet.check.save "$1" Skip 'dig not installed'
    return
  fi
  if output=$(__ak.inet.check.run dig "@$2" +time=1 +tries=1 +short google.com A 2>/dev/null) &&
     printf '%s\n' "$output" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    __ak.inet.check.save "$1" OK
  else
    __ak.inet.check.save "$1" Fail 'no A record'
  fi
}

function __ak.inet.check.doh() {
  local output
  # JSON is parsed structurally when jq exists; Python is the portable fallback.
  local parser=(jq -e '.Status == 0 and (.Answer | type == "array" and length > 0)')
  if ! command -v jq >/dev/null; then
    parser=(python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(not(d.get("Status")==0 and isinstance(d.get("Answer"),list) and len(d["Answer"])>0))')
    if ! command -v python3 >/dev/null; then
      __ak.inet.check.save doh Skip 'jq or python3 required to parse DNS JSON'
      return
    fi
  fi
  if output=$(__ak.inet.check.run curl --noproxy '*' -fsS --connect-timeout 1 --max-time 2 -H 'accept: application/dns-json' \
      'https://1.1.1.1/dns-query?name=google.com&type=A' 2>/dev/null) &&
      printf '%s' "$output" | "${parser[@]}" >/dev/null 2>&1; then
    __ak.inet.check.save doh OK
  else
    __ak.inet.check.save doh Fail 'request failed or invalid DNS response'
  fi
}

function __ak.inet.check.proxy() {
  local output enabled
  [[ "$checkOS" == Darwin ]] || return 0
  __ak.inet.check.save proxy Info 'unavailable (timeout or missing scutil)'
  if ! output=$(__ak.inet.check.run scutil --proxy 2>/dev/null); then return; fi
  enabled=$(printf '%s\n' "$output" | awk '/(HTTP|HTTPS|SOCKS)Enable : 1/{sub(/Enable/,"",$1);printf "%s ",$1}')
  __ak.inet.check.save proxy Info "${enabled:-none}"
}

function __ak.inet.check.tailscale() {
  local binary output name
  command -v jq >/dev/null || return 0
  binary=$(command -v tailscale)
  if [[ -z "$binary" && -x /usr/local/bin/tailscale ]]; then binary=/usr/local/bin/tailscale; fi
  [[ -n "$binary" ]] || return 0
  __ak.inet.check.save tailscale Info 'unavailable (daemon stopped or timeout)'
  if output=$(__ak.inet.check.run "$binary" status --json 2>/dev/null) &&
     name=$(printf '%s' "$output" | jq -er 'if .ExitNodeStatus == null then "none" else (.ExitNodeStatus as $exit | ([.Peer[]? | select(.ID == $exit.ID)][0]) as $peer | $peer.HostName // $peer.DNSName // $exit.HostName // $exit.DNSName // $exit.TailscaleIPs[0] // "unknown") end' 2>/dev/null); then
    __ak.inet.check.save tailscale Info "exit node: $name"
  fi
}

function __ak.inet.check.print() {
  local key label result detail color
  while IFS='|' read -r key label; do
    [[ -f "$checkDir/$key" ]] || continue
    IFS='|' read -r result detail < "$checkDir/$key"
    color=''
    if [[ -t 1 ]]; then
      case "$result" in OK) color=${AK_COLOR_Green:-};; Fail) color=${AK_COLOR_Red:-};; esac
    fi
    printf '%s%-6s %-18s %s%s\n' "$color" "[$result]" "$label" "$detail" "${color:+${AK_COLOR_NC:-}}"
  done <<'ROWS'
link|Link
router|Router
isp|ISP hop
ping1|Ping 1.1.1.1
ping2|Ping 8.8.8.8
tcp1|TCP 1.1.1.1:443
tcp2|TCP 8.8.8.8:443
ipv6|IPv6
system|DNS system
dns1|DNS @1.1.1.1
dns2|DNS @8.8.8.8
doh|DNS over HTTPS
route|Default route
proxy|Proxy
tailscale|Tailscale
ROWS
}

function __ak.inet.check.verdict() {
  local verdict
  if __ak.inet.check.is link Fail; then
    verdict='No network link (Wi-Fi off / no DHCP lease)'
  elif __ak.inet.check.is ping1 OK || __ak.inet.check.is ping2 OK ||
       __ak.inet.check.is tcp1 OK || __ak.inet.check.is tcp2 OK; then
    verdict=$(__ak.inet.check.publicVerdict)
  else
    if ! __ak.inet.check.is router OK; then
      verdict='Router unreachable — Wi-Fi / LAN problem (or router ignores ping)'
    elif __ak.inet.check.is isp Fail; then verdict='Router up, ISP uplink down'
    elif __ak.inet.check.is isp OK; then verdict='ISP reachable, internet beyond it down'
    else verdict='Router up, internet down (ISP or beyond)'
    fi
    if [[ -f "$checkDir/tunnel" ]]; then
      verdict="$verdict; traffic goes through VPN tunnel $(cat "$checkDir/tunnel")"
    fi
  fi
  printf '=> %s\n' "$verdict"
}

function __ak.inet.check.publicVerdict() {
  local key failures=''
  if ! __ak.inet.check.is system OK; then
    if __ak.inet.check.is dns1 OK || __ak.inet.check.is dns2 OK; then
      echo 'Local DNS resolver broken (router / VPN / Tailscale DNS)'
    elif __ak.inet.check.is doh OK; then echo 'Plain DNS (UDP/53) blocked, DNS over HTTPS works'
    else echo 'DNS unreachable'
    fi
    return
  fi
  if __ak.inet.check.is ping1 Fail && __ak.inet.check.is ping2 Fail; then
    echo 'Internet OK (ICMP filtered)'
    return
  fi
  for key in router isp ping1 ping2 tcp1 tcp2 dns1 dns2; do
    if ! __ak.inet.check.is "$key" Fail; then continue; fi
    case "$key" in
      ping1) key='ICMP to 1.1.1.1 filtered';; ping2) key='ICMP to 8.8.8.8 filtered';;
      tcp1) key='TCP 1.1.1.1:443 failed';; tcp2) key='TCP 8.8.8.8:443 failed';;
      dns1) key='DNS @1.1.1.1 failed';; dns2) key='DNS @8.8.8.8 failed';;
      router) key='router ignores ping';; isp) key='ISP hop ignores ping';;
    esac
    failures="${failures}${failures:+; }$key"
  done
  printf 'Internet OK%s\n' "${failures:+ ($failures)}"
}

##
# URL encode script for encoding text.
#
# @param {string} raw a URL to encode
# @returns {string} safe encoded URL
#
# Example:
#
#     $ ak.inet.urlencode "foo bar"
#     foo%20bar
#
# Notes:
# 1. If you are going to use it with `curl` no need to do it! Use `--data-urlencode` & `-G` params for `curl`
# 2. This function works like `encodeURIComponent` (not `encodeURI`) in JS. So, to decode use `decodeURIComponent`.
#
# Script source: https://stackoverflow.com/a/28055173/4843221
# JS fn symbols list: https://stackoverflow.com/a/50943429/4843221
# Alternative native version: https://github.com/SixArm/urlencode.sh/blob/master/urlencode.sh
##
function ak.inet.encodeURIComponent() {
    echo -n "$1" | perl -0777 -pe 's/([^a-zA-Z0-9_.!~*()'\''-])/sprintf("%%%02X", ord($1))/ge'
}

##
# URI script to encode text, for example a CGI query string.
#
# @param {string} encodedUrl
# @returns {string} decoded url
#
# Example:
#
#     $ urldecode "foo%26bar"
#     foo&bar
#
# Original script: https://unix.stackexchange.com/a/272303
# One more solution that doesn't work: https://github.com/SixArm/urldecode.sh/blob/master/urldecode.sh
##
function ak.inet.decodeURIComponent() {
    local -r encodedUrl="${1}"

    echo -ne "$(echo -n "${encodedUrl}" | sed -E "s/%/\\\\x/g")"
}
