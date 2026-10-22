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
source <(sed -n '/^function __device_password () {/,/^alias out=/p' "$repo/aliases" | head -n -1)
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
printf '%s\n' '197 wrong' '97 p a $() `literal` "quote"' > "$PASSWORDFILE"
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
# References resolve beside PASSWORDFILE, regardless of the working directory.
printf '%s\n' '97 ./97 secret.passwd' > "$PASSWORDFILE"
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
[[ $(__device_password 97) == ./literal-password ]] || fail 'recursive reference'
printf '%s\n' '97 ./absent.passwd' > "$PASSWORDFILE"
if rd abc 2>/dev/null; then fail 'missing referenced file accepted'; fi
printf '%s\n' '97 /literal-password' > "$PASSWORDFILE"
[[ $(__device_password 97) == /literal-password ]] || fail 'absolute path must stay literal'
# Empty and single-hyphen passwords are data, including for RDP.
for secret in '' '-'; do
  printf '97 %s\n' "$secret" > "$PASSWORDFILE"
  rd abc
  python3 - "$secret" <<'PYTEST'
import json, os, sys
_, password, env = json.load(open(os.environ['CAPTURE']))
assert password == sys.argv[1] + '\n' and env is None
PYTEST
done
printf '%s\n' '197 wrong' > "$PASSWORDFILE"
if xtv abc 2>/dev/null; then fail 'substring record accepted'; fi
printf '%s\n' '97 p a $() `literal` "quote"' > "$PASSWORDFILE"
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
printf '%s\n' '97 duplicate' >> "$PASSWORDFILE"
if rd abc 2>/dev/null; then fail 'duplicate password accepted'; fi
function sudo () { return 1; }
if xtv abc 2>/dev/null; then fail 'sudo denial ignored'; fi
function sudo () { return 2; }
if xtv abc 2>/dev/null; then fail 'lookup error ignored'; fi
# Explicit authentication bypasses the password file.
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
printf '%s\n' 'desktop integration checks passed'
