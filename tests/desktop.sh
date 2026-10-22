#!/usr/bin/env bash
# Isolated integration checks: no sudo, SSH connections or graphical sessions.
set -eu
repo=$(cd "$(dirname "$0")/.." && pwd)
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT
export XDG_STATE_HOME="$fixture/state" CAPTURE="$fixture/capture" PASSWORDFILE="$fixture/passwords"
export PATH="$fixture/bin:$repo/scripts:$PATH"
mkdir "$fixture/bin"
cat > "$fixture/bin/viewer" <<'PY'
#!/usr/bin/env python3
import json, os, sys
with open(os.environ['CAPTURE'], 'w') as out:
    json.dump([sys.argv[1:], sys.stdin.read(), os.environ.get('DESKTOP_PASSWORD')], out)
PY
chmod +x "$fixture/bin/viewer"
ln -s viewer "$fixture/bin/ssh"
ln -s viewer "$fixture/bin/rdesktop"
ln -s viewer "$fixture/bin/xtightvncviewer"
# Load definitions without shell startup side effects.
source <(sed -n '/^function __device_name () {/,/^alias ips=/p' "$repo/aliases" | head -n -1)
source <(sed -n '/^function __device_read () {/,/^alias out=/p' "$repo/aliases" | head -n -1)
function launch_and_close () { "$@"; }
function sudo () { command "$@"; }
# Stand in for the profile's numeric resolver without depending on local config.
function __lan_resolve_target_token () {
  if [[ $1 == 97 ]]; then printf '%s\n' device97.example
  else printf '%s\n' "$1"; fi
}
fail () { echo "FAIL: $*" >&2; exit 1; }
alias abc=97 chain=abc loop1=loop2 loop2=loop1
[[ $(__device_name chain) == 97 ]] || fail 'alias chain'
if __device_name loop1 >/dev/null 2>&1; then fail 'alias cycle'; fi
alias complex='ssh host'
[[ $(__device_name complex) == complex ]] || fail 'complex alias must not execute'
[[ $(__tunnel_target : "$(__device_name abc)") == device97.example ]] || fail 'numeric alias'
[[ $(__tunnel_target :: 97) == device97.example ]] || fail 'numeric device'
# Quotes, shell syntax and spaces are password data.
printf '%s\n' 'xtv 197 wrong' 'xtv 97 p a $() `literal` "quote"' 'rd 97 p a $() `literal` "quote"' > "$PASSWORDFILE"
xtv abc
python3 - <<'PY'
import json, os
args, password, env = json.load(open(os.environ['CAPTURE']))
assert 'device97.example' in args and '-autopass' in args
assert password == 'p a $() `literal` "quote"\n'
assert env is None and password.strip() not in args
PY
rd 97
python3 - <<'PY'
import json, os
args, password, env = json.load(open(os.environ['CAPTURE']))
assert 'device97.example' in args and args[args.index('-p') + 1] == '-'
assert password == 'p a $() `literal` "quote"\n' and env is None
PY
# Caller identity is part of the key; arbitrary caller names are supported.
printf '%s\n' 'xtv 97 vnc-password' 'rd 97 rdp-password' 'ssh 97 ssh-password' 'curl 97 curl-password' 'custom 97 custom-password' > "$PASSWORDFILE"
for caller in xtv rd ssh curl custom; do
  case $caller in xtv) expected=vnc-password;; rd) expected=rdp-password;; *) expected=$caller-password;; esac
  [[ $(__device_password "$caller" 97) == "$expected" ]] || fail "caller lookup: $caller"
done
for caller in xtv rd; do
  "$caller" abc
  python3 - "$caller" <<'PYTEST'
import json, os, sys
_, password, _ = json.load(open(os.environ['CAPTURE']))
assert password == {'xtv': 'vnc-password\n', 'rd': 'rdp-password\n'}[sys.argv[1]]
PYTEST
done
printf '%s\n' 'ssh 97 only-ssh' > "$PASSWORDFILE"
if rd abc 2>/dev/null; then fail 'password borrowed from another caller'; fi
# References resolve beside PASSWORDFILE, regardless of the working directory.
printf '%s\n' 'xtv 97 ./97 secret.passwd' 'rd 97 ./97 secret.passwd' > "$PASSWORDFILE"
printf '%s\n' 'file p a $() `literal` "quote"' > "$fixture/97 secret.passwd"
for viewer in rd xtv; do
  (cd /; "$viewer" abc)
  python3 - <<'PYTEST'
import json, os
args, password, env = json.load(open(os.environ['CAPTURE']))
assert password == 'file p a $() `literal` "quote"\n' and env is None
assert './97 secret.passwd' not in args
PYTEST
done
# File contents remain literal, including text starting with ./.
printf '%s\n' './literal-password' > "$fixture/97 secret.passwd"
[[ $(__device_password rd 97) == ./literal-password ]] || fail 'recursive reference'
printf '%s\n' 'rd 97 ./absent.passwd' > "$PASSWORDFILE"
if rd abc 2>/dev/null; then fail 'missing referenced file accepted'; fi
printf '%s\n' 'rd 97 /literal-password' > "$PASSWORDFILE"
[[ $(__device_password rd 97) == /literal-password ]] || fail 'absolute path must stay literal'
# Empty and single-hyphen passwords are data, including for RDP.
for secret in '' '-'; do
  printf 'rd 97 %s\n' "$secret" > "$PASSWORDFILE"
  rd abc
  python3 - "$secret" <<'PYTEST'
import json, os, sys
_, password, env = json.load(open(os.environ['CAPTURE']))
assert password == sys.argv[1] + '\n' and env is None
PYTEST
done
printf '%s\n' 'xtv 197 wrong' > "$PASSWORDFILE"
# With no terminal, leave prompting to the viewer; never use a substring match.
xtv abc </dev/null
python3 - <<'PYTEST'
import json, os
args, password, _ = json.load(open(os.environ['CAPTURE']))
assert 'device97.example' in args and '-autopass' not in args and password == ''
PYTEST
# A real terminal must reach the existing hidden password prompt.
declare -f > "$fixture/functions"
python3 - "$fixture/functions" <<'PYTEST'
import json, os, pty, select, subprocess, sys, time
for target in ('abc', 'desktop.example:7'):
    master, slave = pty.openpty()
    process = subprocess.Popen(
        ['bash', '-c', 'source "$1"; xtv "$2"', 'bash', sys.argv[1], target],
        stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    output = b''
    try:
        deadline = time.monotonic() + 5
        while b'VNC password (empty if none): ' not in output:
            remaining = deadline - time.monotonic()
            assert remaining > 0 and select.select([master], [], [], remaining)[0], output
            output += os.read(master, 4096)
        os.write(master, b'prompted-secret\n')
        assert process.wait(timeout=5) == 0
        args, password, env = json.load(open(os.environ['CAPTURE']))
        expected = 'device97.example' if target == 'abc' else target
        assert expected in args and '-autopass' in args
        assert password == 'prompted-secret\n' and env is None
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
PYTEST
printf '%s\n' 'rd 97 p a $() `literal` "quote"' 'xtv 97 p a $() `literal` "quote"' > "$PASSWORDFILE"
# A registered bare name wins over the direct device address.
port=$(getport 97 2>/dev/null)
[[ $(__tunnel_target :: "$(__device_name abc)") == "127.0.0.1::$port" ]] || fail 'bare registered name'
rd abc
python3 - "$port" <<'PY'
import json, os, sys
args, password, env = json.load(open(os.environ['CAPTURE']))
assert '127.0.0.1:' + sys.argv[1] in args and password.startswith('p a ')
PY
ssh -J gateway user@abc
python3 - "$port" <<'PYTEST'
import json, os, sys
args, _, _ = json.load(open(os.environ['CAPTURE']))
assert args == ['-p', sys.argv[1], '-o', 'HostKeyAlias=97', '-J', 'gateway', 'user@127.0.0.1']
PYTEST
# Named forwards remain compatible.
named=$(getport gateway:desktop 2>/dev/null)
[[ $(__tunnel_target :: gateway:desktop) == "127.0.0.1::$named" ]] || fail 'named forward'
# Unknown lookups never allocate.
[[ $(__tunnel_target : absent) == absent ]] || fail 'literal fallback'
if getport --lookup absent; then fail 'lookup allocated'; fi
printf '%s\n' 'rd 97 duplicate' >> "$PASSWORDFILE"
if rd abc 2>/dev/null; then fail 'duplicate password accepted'; fi
function sudo () { return 1; }
if xtv abc 2>/dev/null; then fail 'sudo denial ignored'; fi
function sudo () { return 2; }
if xtv abc 2>/dev/null; then fail 'lookup error ignored'; fi
# Explicit authentication bypasses credential loading; routing still reads the record.
printf '%s\n' 'rd 97 ./missing-secret' 'xtv 97 ./missing-secret' > "$PASSWORDFILE"
function sudo () { command "$@"; }
rd abc -p explicit
python3 - <<'PYTEST'
import json, os
args, password, _ = json.load(open(os.environ['CAPTURE']))
assert 'explicit' not in args and password == 'explicit\n'
PYTEST
xtv abc -passwd /example/file
# Check generated forwarding arguments without opening any network connection.
function ssh () { printf '%s\n' "$@" > "$CAPTURE"; }
sshh gateway desktop:host:5900 2>/dev/null
rg -q -F -- "127.0.0.1:$named:host:5900" "$CAPTURE" || fail 'sshh forward'
# Allocation is stable even before a listener exists.
[[ $(getport 97) == "$port" && $(getport 97) == "$port" ]] || fail 'unstable allocation'
# The SSH fixture owns forwarding state; viewers only record their arguments.
rm "$fixture/bin/ssh"
export TUNNEL_LOG="$fixture/tunnels" TUNNEL_STATE="$fixture/forwards"
cat > "$fixture/bin/ssh" <<'PYSSH'
#!/usr/bin/env python3
import json, os, pathlib, sys
args = sys.argv[1:]
with open(os.environ['TUNNEL_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\n')
if '-O' in args and '-L' not in args:
    sys.exit(0 if pathlib.Path(os.environ['TUNNEL_STATE']).exists() else 1)
if '-L' not in args:
    with open(os.environ['CAPTURE'], 'w') as out:
        json.dump([args, '', None], out)
    sys.exit(0)
forward = args[args.index('-L') + 1]
state = pathlib.Path(os.environ['TUNNEL_STATE'])
if '-O' in args:
    if not state.exists(): sys.exit(1)
    forwards = state.read_text().splitlines()
    if forward not in forwards: state.write_text('\n'.join(forwards + [forward]) + '\n')
else:
    if os.environ.get('SSH_START_FAIL'): sys.exit(1)
    state.write_text(forward + '\n')
PYSSH
chmod +x "$fixture/bin/ssh"
# First row is the bare default; services have independent ports and credentials.
printf '%s\n' 'xtv a97 gateway desktop.example:5900 ./97 secret.passwd' \
  'rd a97 gateway desktop.example:3389 rdp-secret' \
  'ssh a97 gateway desktop.example:22 ignored-ssh-password' > "$PASSWORDFILE"
printf '%s\n' 'vnc-secret' > "$fixture/97 secret.passwd"
export SUDO_LOG="$fixture/sudo"
function sudo () { printf '%s\n' "$1" >> "$SUDO_LOG"; command "$@"; }
command_not_found_handle a97
vncport=$(getport --lookup xtv:a97)
python3 - "$vncport" <<'PYTEST'
import json, os, sys
args, secret, _ = json.load(open(os.environ['CAPTURE']))
assert '127.0.0.1::' + sys.argv[1] in args and secret == 'vnc-secret\n'
calls = [json.loads(line) for line in open(os.environ['TUNNEL_LOG'])]
assert len(calls) == 3 and 'forward' in calls[0] and 'check' in calls[1] and '-fNT' in calls[2]
assert '-o' in calls[2] and 'ExitOnForwardFailure=yes' in calls[2]
assert calls[2][calls[2].index('-L') + 1] == '127.0.0.1:' + sys.argv[1] + ':desktop.example:5900'
assert open(os.environ['SUDO_LOG']).read().splitlines() == ['awk', 'cat']
PYTEST
xtv a97
[[ $(wc -l < "$TUNNEL_LOG") == 4 ]] || fail 'existing tunnel restarted'
rd a97
rdport=$(getport --lookup rd:a97)
[[ $rdport != "$vncport" ]] || fail 'services share a port'
# Drop the test's ssh override so the real wrapper exercises its route.
unset -f ssh
source <(sed -n '/^function ssh () {/,/^# Keep forwards/p' "$repo/aliases" | head -n -1)
ssh user@a97 echo ok
python3 - <<'PYTEST'
import json, os
args, _, _ = json.load(open(os.environ['CAPTURE']))
assert 'user@127.0.0.1' in args and 'HostKeyAlias=a97' in args and args[-2:] == ['echo', 'ok']
PYTEST
# A dead master restarts on the next invocation; failed startup never launches a viewer.
rm "$TUNNEL_STATE"
xtv a97
rm "$TUNNEL_STATE" "$CAPTURE"
export SSH_START_FAIL=1
if xtv a97; then fail 'failed tunnel accepted'; fi
[[ ! -e $CAPTURE ]] || fail 'viewer launched after tunnel failure'
unset SSH_START_FAIL
# Direct routes never open SSH. Explicit auth still resolves routing.
printf '%s\n' 'xtv direct - desktop.example:5901 ./missing-secret' > "$PASSWORDFILE"
xtv direct -passwd /explicit
python3 - <<'PYTEST'
import json, os
args, _, _ = json.load(open(os.environ['CAPTURE']))
assert 'desktop.example::5901' in args and '/explicit' in args
PYTEST
# Duplicate keys, malformed routes and denied reads stop before side effects.
printf '%s\n' 'xtv bad gateway desktop.example:70000 secret' > "$PASSWORDFILE"
if xtv bad 2>/dev/null; then fail 'invalid remote port accepted'; fi
printf '%s\n' 'xtv bad gateway desktop.example:5900 secret' 'xtv bad gateway other.example:5900 secret' > "$PASSWORDFILE"
if xtv bad 2>/dev/null; then fail 'duplicate route accepted'; fi
function sudo () { [[ $1 != cat ]] || return 1; command "$@"; }
printf '%s\n' 'xtv bad gateway desktop.example:5900 ./denied' > "$PASSWORDFILE"
if xtv bad 2>/dev/null; then fail 'denied referenced file accepted'; fi
function sudo () { return 1; }
if xtv a97 -passwd /explicit 2>/dev/null; then fail 'denied route read bypassed by explicit auth'; fi
if command_not_found_handle a97 2>/dev/null; then fail 'denied dispatch read accepted'; fi
printf '%s\n' 'desktop integration checks passed'
