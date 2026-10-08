#!/usr/bin/env bash
# Offline contract tests of the parallel ak.sudo.remote-* commands (lend-many,
# revoke-many, status-all), in bash AND zsh. A fake ssh on PATH answers by host
# name prefix; no network, no password, no host is touched. The contract: one
# result line per distinct host (a duplicate dropped with a warning), a summary
# line with counts, and a non-zero exit code when any host was not handled.
#
# Run: bash tests/sudo-remote.test.sh
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin" "$fixture/tmp"

# Host name prefix → behaviour:
#   ok-*     reachable, ankor-shell current, sudo passwordless; lend/revoke work
#   nores-*  ssh cannot resolve the HostName (rc 255, like a dead MagicDNS name)
#   hang-*   DNS/connect hangs until the ak.sh.timeout deadline (rc 124)
#   noak-*   no ankor-shell on the host (rc 127)
#   old-*    ankor-shell without the lend_api marker (outdated)
#   denied-* ssh key rejected (rc 255)
#   slow-*   the probe answers, the lend hangs
cat > "$fixture/bin/ssh" <<'FAKE'
#!/usr/bin/env bash
while (( $# > 0 )) && [[ $1 != -- ]]; do shift; done
shift
host=$1
cmd=$2
case "$host" in
  nores-*)
    echo "ssh: Could not resolve hostname ${host}.example.internal: nodename nor servname provided, or not known" >&2
    exit 255 ;;
  denied-*) echo "${host}: Permission denied (publickey)." >&2; exit 255 ;;
  hang-*) exec sleep 8 ;;
  noak-*) exit 127 ;;
esac
deadline=$(( $(date +%s) + 1200 ))
case "$cmd" in
  *'ak.sudo.lend --password-fd'*)
    [[ $host == slow-* ]] && exec sleep 8
    echo "granted=1 deadline_epoch=${deadline} lend_api=1" ;;
  *'ak.sudo.revoke;'*)
    echo "granted=1 deadline_epoch=${deadline} lend_api=1"
    echo "granted=0 lend_api=1" ;;
  *)
    if [[ $host == old-* ]]; then echo 'granted=0'; else echo 'granted=0 lend_api=1'; fi
    echo 'nopasswd=1' ;;
esac
FAKE
chmod +x "$fixture/bin/ssh"

cat > "$fixture/ssh_config" <<'CFG'
Host ok-a nores-b
  User deploy
Host hang-d noak-e
  User deploy
CFG

export PATH="$fixture/bin:$PATH" TMPDIR="$fixture/tmp" AK_SSH_CONFIG="$fixture/ssh_config"
export AK_SUDO_REMOTE_ALL_TIMEOUT=2 AK_SUDO_REMOTE_MANY_TIMEOUT=2

passes=0
failures=0

function check() {
  local -r name=$1
  shift
  if "$@"; then
    passes=$(( passes + 1 ))
    return 0
  fi
  failures=$(( failures + 1 ))
  printf 'FAIL [%s] %s\n' "$shell" "$name" >&2
  printf '%s\n' "$out" | sed 's/^/      | /' >&2
}

function hasLine() { grep -qE -- "$1" <<< "$out"; }

# One result line per host: `[✔✘·] <host>  …` (status-all has no mark).
function hasOneLinePerHost() {
  local -r expected=$1
  shift
  local -i lines=0
  lines=$(grep -cE '^([✔✘·] )?[a-z]+-[a-z]+  ' <<< "$out" || true)
  (( lines == expected )) || return 1
  local host=''
  for host in "$@"; do
    [[ $(grep -cE "^([✔✘·] )?${host}  " <<< "$out" || true) == 1 ]] || return 1
  done
}

# Run <command> in a fresh <shell> with ankor-shell loaded; prints its output
# then `rc=<exit code>`.
function runIn() {
  local -r sh=$1
  local -r command=$2
  "$sh" -c "trap : INT; source '$repo/index.sh' > /dev/null 2>&1; $command; echo \"rc=\$?\"" 2>&1
}

shells=(bash)
command -v zsh > /dev/null && shells+=(zsh)

for shell in "${shells[@]}"; do
  # The reported case: resolution fails for two hosts, one hangs, the rest lend.
  out=$(runIn "$shell" 'ak.sudo.remote-lend-many 20 ok-a nores-b ok-c hang-d ok-e nores-f ok-a')
  check 'lend-many: one line per host' hasOneLinePerHost 6 ok-a nores-b ok-c hang-d ok-e nores-f
  check 'lend-many: duplicate noted' hasLine "duplicate host 'ok-a' ignored"
  check 'lend-many: DNS reason' hasLine '^✘ nores-b +hostname does not resolve \(DNS\)'
  check 'lend-many: ssh stderr shown' hasLine '^    ssh: Could not resolve hostname nores-f'
  check 'lend-many: hang reason' hasLine '^✘ hang-d +unreachable \(timeout'
  check 'lend-many: lent hosts' hasLine '^✔ ok-e +20m  until'
  check 'lend-many: summary' hasLine '^3 lent / 3 unreachable / 0 skipped / 0 failed \(6 hosts\)$'
  check 'lend-many: rc 1' hasLine '^rc=1$'

  out=$(runIn "$shell" 'ak.sudo.remote-lend-many 20 ok-a noak-b old-c denied-d')
  check 'lend-many kinds: one line per host' hasOneLinePerHost 4 ok-a noak-b old-c denied-d
  check 'lend-many kinds: no ankor-shell' hasLine '^✘ noak-b +ankor-shell not installed'
  check 'lend-many kinds: outdated' hasLine '^✘ old-c +ankor-shell outdated'
  check 'lend-many kinds: auth' hasLine '^✘ denied-d +ssh auth failed'
  check 'lend-many kinds: summary' hasLine '^1 lent / 1 unreachable / 0 skipped / 2 failed \(4 hosts\)$'
  check 'lend-many kinds: rc 1' hasLine '^rc=1$'

  out=$(runIn "$shell" 'ak.sudo.remote-lend-many 20 ok-a,ok-b')
  check 'lend-many all ok: summary' hasLine '^2 lent / 0 unreachable / 0 skipped / 0 failed \(2 hosts\)$'
  check 'lend-many all ok: rc 0' hasLine '^rc=0$'

  # Ctrl-C while a lend hangs: the waiting hint names the host, the summary
  # still lists it (interrupted, state unknown), rc 130.
  intOut="$fixture/int-$shell.out"
  set -m
  ( AK_SUDO_REMOTE_MANY_TIMEOUT=20 runIn "$shell" 'ak.sudo.remote-lend-many 20 ok-a slow-b' > "$intOut" ) &
  intPid=$!
  set +m
  for (( t = 0; t < 100; t++ )); do
    grep -q 'still waiting for slow-b' "$intOut" 2> /dev/null && break
    sleep 0.1
  done
  kill -INT -- "-$intPid" 2> /dev/null || true
  wait "$intPid" || true
  out=$(cat "$intOut")
  check 'lend-many INT: waiting hint' hasLine 'still waiting for slow-b \(deadline 20s'
  check 'lend-many INT: one line per host' hasOneLinePerHost 2 ok-a slow-b
  check 'lend-many INT: pending host listed' hasLine '^✘ slow-b +interrupted before its result'
  check 'lend-many INT: summary' hasLine '^1 lent / 0 unreachable / 0 skipped / 1 failed \(2 hosts\)$'
  check 'lend-many INT: rc 130' hasLine '^rc=130$'

  out=$(runIn "$shell" 'ak.sudo.remote-revoke-many ok-a nores-b ok-c hang-d noak-e ok-a')
  check 'revoke-many: one line per host' hasOneLinePerHost 5 ok-a nores-b ok-c hang-d noak-e
  check 'revoke-many: duplicate noted' hasLine "duplicate host 'ok-a' ignored"
  check 'revoke-many: DNS reason' hasLine '^✘ nores-b +hostname does not resolve \(DNS\)'
  check 'revoke-many: summary' hasLine '^2 revoked / 0 no grant / 2 unreachable / 1 failed$'
  check 'revoke-many: rc 1' hasLine '^rc=1$'

  out=$(runIn "$shell" 'ak.sudo.remote-status-all')
  check 'status-all: one line per host' hasOneLinePerHost 4 ok-a nores-b hang-d noak-e
  check 'status-all: DNS reason' hasLine '^nores-b +hostname does not resolve \(DNS\)'
  check 'status-all: hang reason' hasLine '^hang-d +unreachable \(timeout'
  check 'status-all: summary' hasLine '^0 granted / 1 no grant / 2 unreachable / 1 without ankor-shell$'
  check 'status-all: rc 0 (a report)' hasLine '^rc=0$'
done

printf '%d passed, %d failed (%s)\n' "$passes" "$failures" "${shells[*]}"
(( failures == 0 ))
