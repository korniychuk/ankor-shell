#!/usr/bin/env bash
# Offline contract tests; no host network utilities are reachable through PATH.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
mkdir "$fixture/bin" "$fixture/tmp"
export TEST_ROOT=$fixture TEST_REPO=$repo TMPDIR=$fixture/tmp
for tool in awk sed head cut grep uname mktemp rm find perl sleep cat jq python3; do
  ln -s "$(command -v "$tool")" "$fixture/bin/$tool"
done
rm "$fixture/bin/uname"
cat > "$fixture/bin/fake" <<'FAKE'
#!/opt/homebrew/bin/bash
name=${0##*/}
echo "$$" >> "$TEST_ROOT/probe-pids"
[[ ${IGNORE_TERM:-0} == 0 ]] || trap '' TERM
case "$name" in
  uname) echo "${TEST_OS:-Darwin}";;
  route)
    iface=en0
    [[ $SCENARIO == vpn* ]] && iface=utun7
    printf 'gateway: 192.0.2.1\ninterface: %s\n' "$iface";;
  netstat) printf 'default 192.0.2.99 UGScI en9\ndefault 192.0.2.1 UGSc en0\n';;
  ifconfig)
    [[ $SCENARIO == no_link ]] && exit 0
    [[ $SCENARIO == apipa ]] && { echo 'inet 169.254.1.2'; exit; }
    echo 'inet 192.0.2.2 netmask 0xffffff00';;
  ip)
    if [[ $* == *addr* ]]; then echo 'inet 192.0.2.2/24';
    elif [[ $SCENARIO == vpn* ]]; then printf 'default dev tun0\ndefault via 192.0.2.1 dev eth0\n';
    else echo 'default via 192.0.2.1 dev eth0'; fi;;
  ping|ping6|nc|dig|dscacheutil|getent|traceroute)
    [[ ${DELAY:-0} == 0 ]] || sleep "$DELAY"
    case "$name" in
      ping|ping6)
        target=${!#}
        [[ $SCENARIO == ipv6_fail && $name == ping6 ]] && exit 1
        [[ $SCENARIO == router_fail ]] && exit 1
        [[ $SCENARIO == beyond && $target != 192.0.2.1 && $target != 198.51.100.1 ]] && exit 1
        [[ $SCENARIO == icmp || $SCENARIO == no_link ]] && exit 1
        [[ $SCENARIO == down* || $SCENARIO == vpn_down ]] && [[ $target != 192.0.2.1 ]] && exit 1
        [[ $SCENARIO == partial && $target == 8.8.8.8 ]] && exit 1
        echo '64 bytes: time=13.2 ms';;
      nc) [[ $SCENARIO != router_fail && $SCENARIO != beyond && $SCENARIO != down* && $SCENARIO != vpn_down && $SCENARIO != no_link ]];;
      dscacheutil|getent)
        [[ $SCENARIO == local_dns || $SCENARIO == doh* || $SCENARIO == down* ]] && exit 0
        echo 'ip_address: 192.0.2.80';;
      dig)
        [[ $SCENARIO == doh* || $SCENARIO == down* ]] && exit 0
        echo '192.0.2.80';;
      traceroute)
        [[ $SCENARIO == down_nohop ]] && exit 0
        echo '2 198.51.100.1 1.2 ms';;
    esac;;
  curl)
    [[ ${DELAY:-0} == 0 ]] || sleep "$DELAY"
    echo called >> "$TEST_ROOT/doh-calls"
    [[ $SCENARIO == doh_bad ]] && { echo '{"Status":0,"Answer":[]}'; exit; }
    [[ $SCENARIO == down* ]] && exit 1
    echo '{"Status":0,"Answer":[{"type":1,"data":"192.0.2.80"}]}';;
  scutil) echo 'HTTPEnable : 0';;
  tailscale)
    if [[ $SCENARIO == exit_node ]]; then
      echo '{"ExitNodeStatus":{"ID":"node-id"},"Peer":{"nodekey:example":{"ID":"node-id","HostName":"vpn-example"}}}'
    else echo '{"ExitNodeStatus":null}'; fi;;
  *) exit 99;;
esac
FAKE
# Use the current Bash 5 on Linux as well as macOS.
sed "1s|.*|#!$(command -v bash)|" "$fixture/bin/fake" > "$fixture/bin/runner"
chmod +x "$fixture/bin/runner"
for tool in uname route netstat ifconfig ip ping ping6 nc dig dscacheutil getent traceroute curl scutil tailscale; do
  ln -s runner "$fixture/bin/$tool"
done
export TEST_PATH=$fixture/bin
export TEST_BASH
TEST_BASH=$(command -v bash)
export TEST_ZSH
TEST_ZSH=$(command -v zsh)
python3 <<'PY'
import os, pathlib, re, signal, subprocess, time
root = pathlib.Path(os.environ['TEST_ROOT'])
env = dict(os.environ, PATH=os.environ['TEST_PATH'])
command = 'source "$TEST_REPO/sdk/inet.sh"; ak.inet.check'
labels = ['Link','Router','ISP hop','Ping 1.1.1.1','Ping 8.8.8.8','TCP 1.1.1.1:443',
          'TCP 8.8.8.8:443','IPv6','DNS system','DNS @1.1.1.1','DNS @8.8.8.8',
          'DNS over HTTPS','Default route','Proxy','Tailscale']
cases = {
 'ok': (0, 'Internet OK'),
 'exit_node': (0, 'Internet OK'),
 'ipv6_fail': (0, 'Internet OK'),
 'apipa': (0, 'No network link'),
 'router_fail': (1, 'Router unreachable'),
 'beyond': (1, 'ISP reachable, internet beyond it down'),
 'icmp': (0, 'Internet OK (ICMP filtered)'),
 'partial': (0, 'Internet OK (ICMP to 8.8.8.8 filtered)'),
 'local_dns': (1, 'Local DNS resolver broken'),
 'doh': (1, 'Plain DNS (UDP/53) blocked'),
 'doh_bad': (1, 'DNS unreachable'),
 'down': (1, 'Router up, ISP uplink down'),
 'down_nohop': (1, 'Router up, internet down (ISP or beyond)'),
 'no_link': (1, 'No network link'),
 'vpn': (0, 'Internet OK'),
 'vpn_down': (1, 'traffic goes through VPN tunnel'),
}
def run(shell, scenario, **extra):
    result = subprocess.run(shell + ['-c',command], env=dict(env,SCENARIO=scenario,**extra),
                            text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=6)
    assert not result.stderr, result.stderr
    assert not list((root/'tmp').iterdir()), 'temporary directory leaked'
    rows = re.findall(r'^\[(OK|Fail|Skip|Info)\]\s+(.*?)(?:\s{2,}|$)',result.stdout,re.M)
    positions = [labels.index(label) for _,label in rows]
    assert positions == sorted(set(positions)), result.stdout
    assert len(rows) >= 11, result.stdout
    assert not re.search(r'\[\d+\]|\bdone\b|terminated',result.stdout), result.stdout
    return result,dict((label,state) for state,label in rows)
for shell in ([os.environ['TEST_BASH']], [os.environ['TEST_ZSH'],'-f']):
    for scenario,(code,verdict) in cases.items():
        calls=root/'doh-calls'
        calls.unlink(missing_ok=True)
        result,rows=run(shell,scenario)
        assert result.returncode == code, (scenario,result)
        assert verdict in result.stdout.splitlines()[-1], (scenario,result.stdout)
        assert rows['DNS system'] == ('Fail' if scenario in ('local_dns','doh','doh_bad','down','down_nohop') else 'OK')
        if scenario == 'ok':
            assert all(state in ('OK','Info') for state in rows.values()), rows
            assert not calls.exists(), 'unnecessary DoH request'
        if scenario == 'exit_node':
            assert 'exit node: vpn-example' in result.stdout
        if scenario.startswith('vpn'):
            assert 'ISP hop' not in rows and 'VPN tunnel' in result.stdout
            assert '192.0.2.1' in result.stdout
    result,rows=run(shell,'ok',TEST_OS='Linux')
    assert 'Proxy' not in rows and 'eth0' in result.stdout
    start=time.monotonic()
    result,rows=run(shell,'ok',DELAY='1')
    elapsed=time.monotonic()-start
    assert elapsed < 3, elapsed
    print(f'{shell[0]}: scenarios and parallelism passed ({elapsed:.2f}s)')
    start=time.monotonic()
    result,rows=run(shell,'down',DELAY='10',IGNORE_TERM='1')
    assert time.monotonic()-start < 3.6, 'deadline exceeded'
    assert result.returncode == 1
# Missing tools must never fall through to host network binaries.
if not os.access('/usr/local/bin/tailscale',os.X_OK):
    (root/'bin/tailscale').unlink()
    _,rows=run([os.environ['TEST_BASH']],'ok')
    assert 'Tailscale' not in rows
for tool,label in [('dig','DNS @1.1.1.1'),('dscacheutil','DNS system'),('nc','TCP 1.1.1.1:443')]:
    (root/'bin'/tool).unlink()
    _,rows=run([os.environ['TEST_BASH']],'ok')
    assert rows[label] == 'Skip', rows
    (root/'bin'/tool).symlink_to('runner')
# Absence of jq suppresses Tailscale even if a host has the absolute fallback.
(root/'bin/jq').unlink()
for shell in ([os.environ['TEST_BASH']], [os.environ['TEST_ZSH'],'-f']):
    _,rows=run(shell,'ok')
    assert 'Tailscale' not in rows
    result,_=run(shell,'doh')
    assert 'DNS over HTTPS works' in result.stdout
# Exercise an interactive shell (job notifications would be captured on stderr).
run([os.environ['TEST_ZSH'],'-fi'],'ok')
# SIGINT is sent to the foreground process group, as a terminal sends Ctrl+C.
for shell in ([os.environ['TEST_BASH']], [os.environ['TEST_ZSH'],'-f']):
    proc=subprocess.Popen(shell+['-c',command],env=dict(env,SCENARIO='ok',DELAY='10'),
                          stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    time.sleep(.3)
    os.killpg(proc.pid,signal.SIGINT)
    proc.communicate(timeout=4)
    assert proc.returncode in (130,-signal.SIGINT), proc.returncode
    assert not list((root/'tmp').iterdir()), 'Ctrl+C leaked temporary directory'
# Every probe is a process-group leader, so this also detects orphaned children.
for pid in set((root/'probe-pids').read_text().splitlines()):
    try:
        os.killpg(int(pid),0)
    except ProcessLookupError:
        continue
    raise AssertionError(f'probe process group leaked: {pid}')
print('All offline inet-check tests passed')
PY
