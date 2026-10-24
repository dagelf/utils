# dagelf utils

Linux CLI helpers: bash aliases plus small scripts. Read anything before you run it.

    git clone --depth 1 https://github.com/dagelf/utils && utils/install.sh   # shell, screen and system defaults (sudo)
    utils/install.sh --user                                                 # shell and personal screen defaults only
    utils/install.sh --uninstall                                            # teardown; add --user for user setup only

The repo is sourced where it sits, so `git pull` (`gm`) updates it live. To review first: `gf` fetches and shows the incoming diff, then `gg` merges it (fast-forward only, signed commits only). Put machine-specific vars (`SERVERS`, `RES`, `WIN_USER`, `WIN_PASS`) in `~/.bashrc` above the hook line.

Some highlights:

- `a cmd` runs a command on every host in `$SERVERS` in parallel, output prefixed and sorted (`aa` in series, `aaa` unsorted)
- `ls` groups files by date with separators; `du` sorts by size; `df` hides loop/tmpfs noise
- `f [query]` jumps to a window by fuzzy title; `u`/`uu` fuzzy-search and install packages (yay/pacman)
- `g [msg]` commits all and pushes (msg defaults to `...`); `gf` / `gg` review then merge upstream
- `tldr cmd` quick usage examples from cheat.sh; `z file` strips blank lines and comments
- `send host port cmd` pipes a command's output to a TCP port, no netcat needed
- `lsofkill 3000 :8080` sends SIGTERM to TCP listeners and reports each PID and process name
- `getport [name]` allocates or looks up a persistent port; `sshh` uses these names for SSH forwards (see below)
- `ds container shell` snapshots a container and opens a shell in the copy; `dip` lists container IPs, names and ports
- `hostthis [port]` serves the current dir over HTTP with caddy, behind a password (`hostthis1` without)
- `sk host` copies your ssh key to a host, generating one if needed
- `t2h < log` turns `[seconds-since-boot]` stamps into wall-clock times, counting from this machine's last boot (wrong for older boots or other hosts)
- `ut2h [ts]` turns 10-digit unix timestamps into wall-clock times, in args or piped text
- `popline file [n]` removes and prints the last n lines; `waitall string` waits for matching processes to exit
- `dockertags image [filter]` lists Docker Hub tags
- `git-remote-add host:path` sets up a push-to-deploy remote
- `checklimits.sh` shows system limits against sane defaults
- `macs` looks up MAC vendors; `apt-history.py` and `dpkg-l-by-date.py` show what was installed when

See `AGENTS.md` for the layout and how to merge older copies.

## Ports and SSH tunnels

Reload after updating: `source ~/utils/aliases`. The SSH wrapper preserves optional numeric-host resolution and terminal-title hooks from your profile.

### Port registry

```bash
getport myapp               # allocate if new; otherwise return the same port
getport --lookup myapp      # raw registry lookup, without checking or changing anything
port=$(getport)             # allocate a fresh port; print its generated name to stderr
getport --list              # list registered ports and names, ordered by port
getport --clean             # release unused ports; print the removed port/name rows
```

Ports start at 10000; released ports are reused before allocating higher numbers. With no name, each call gets a fresh allocation named `<caller-basename>:<port>`, for example `deploy.sh:10001`. The caller is the parent command, or its script filename for common interpreters; interactive shells and `bash -c` use `bash`. The generated name goes to stderr as `getport: deploy.sh:10001`. Stdout contains only the number, so command substitution works.

Normal calls also print `http://myapp.localhost:10000` to stderr; stdout stays
numeric. Names are lowercased and converted to DNS labels (up to 63 characters).
The registered port keeps origins distinct even when names normalize alike.
Use the printed URL in the browser and bind the app to loopback on that port.

`getport name` always returns the stored port, even before a listener starts or
after it closes, unless explicitly released with `--clean`.
`getport --lookup name` only reads: absent names exit 1 silently, other errors
exit 2. A conflicting listener causes SSH to fail instead of changing the port.
Lookup does not print a URL. `--list` also only reads; both list and cleanup
print tab-separated port/name rows. `--clean` checks TCP and UDP on IPv4 and
IPv6, keeps occupied ports, and releases unused assignments in one transaction.
Stopped apps lose their saved assignments; released ports can be reused.
Port availability is a snapshot, not a reservation against another process
starting immediately afterwards. Cleanup does not clear browser service workers.

### Named forwards

```bash
sshh abc a:host1:3389 b:host2:3389 c:host3:22
```

This opens one foreground SSH connection to `abc`, forwarding local loopback ports allocated by `getport abc:a`, `getport abc:b`, and `getport abc:c`. Destination names are resolved by the remote gateway. In another terminal:

```bash
rd abc:a                   # rdesktop connects to 127.0.0.1:<registered port>
rd abc:b
ssh abc:c                  # SSH connects to 127.0.0.1 on that registered port
ssh user@abc:c              # specify the destination SSH user
```

Syntax: `sshh host [[name:][target:]port]...`. Each forward accepts:

| Forward | Registry name for gateway `abc` | Remote destination |
| --- | --- | --- |
| `3389` | `abc:1` for the first argument, `abc:2` for the second, etc. | `127.0.0.1:3389` |
| `a:3389` or `a::3389` | `abc:a` | `127.0.0.1:3389` |
| `a:host1:3389` | `abc:a` | `host1:3389` |
| `:host1:3389` | `abc:1` for the first argument, etc. | `host1:3389` |
| `a:[::1]:3389` | `abc:a` | IPv6 loopback port 3389 |

Two fields mean `name:port`; use a leading colon for an unnamed remote target. Unnamed forwards use their argument position, including any named forwards before them. For `sshh user@abc ...`, the registry prefix is still `abc`.

For VNC, `sshh abc desktop:host1:5900`, then `xtv abc:desktop`. `rd` and `xtv` resolve their first argument and pass remaining options through. VNC receives `127.0.0.1::<port>` (an explicit TCP port, not a display number). Literal destinations keep working. The SSH wrapper resolves the destination after SSH options and uses the registry name as `HostKeyAlias`, keeping host-key identities separate. Unknown names do not allocate ports.

`sshh` prints the requested mappings before connecting. It refuses duplicate names within a request and locks each name for the connection's lifetime, so simultaneous starts cannot compete for the same named forward. Disjoint names can use separate connections to the same gateway. SSH exits if any local forward cannot bind; an occupied registered port is never silently reassigned. It uses a separate connection, so closing it leaves other SSH sessions alone. Ctrl-C closes all its forwards. A broken connection is detected by SSH keepalives (15 seconds, three unanswered probes, approximately 45 seconds); it then exits without reconnecting. These are standard [OpenSSH forwarding and keepalive options](https://man.openbsd.org/ssh_config).

No SSH config entries are created and no service detection is needed: use `ssh` for an SSH destination, `rd` for RDP, or `xtv` for VNC. Registered names remain available for the next `sshh` run after a tunnel closes; they do not imply a live connection.

### Device aliases, routes and passwords

Set `export PASSWORDFILE="$HOME/.passwordfile"` in your shell profile. The main
file and referenced files may be root-owned with mode 600. Each routed row is:

```text
# caller alias gateway destination:port password-or-file
xtv workstation gateway desktop.example:5900 ./vnc.passwd
rd workstation gateway desktop.example:3389 password with spaces
ssh workstation gateway desktop.example:22 ./ssh.passwd
xtv direct - desktop.example:5900 ./vnc.passwd
```

`xtv workstation`, `rd workstation` and `ssh workstation` select their own row.
Bare `workstation` uses the first matching caller, here `xtv`. Duplicate
caller/alias keys fail. Named rows override numeric address expansion. Real shell
commands/functions/aliases retain normal precedence. Single-word Bash aliases
(`alias desk=workstation`) still work; cycles fail and command text is not evaluated.

The main file is read once per invocation with `sudo awk`, including bare
dispatch. `./` references are read once with `sudo cat`, relative to the main
file's directory, without recursive expansion. Other passwords remain literal,
including spaces. Trailing newlines from referenced files are stripped.
Credentials are resolved before desktop tunnels open; denied reads, malformed
routes, duplicate keys and tunnel failures stop the launch. Explicit `rd -p ...`
and VNC authentication options bypass credentials, but still read routing.

Legacy `caller alias password-or-file` rows remain valid without routing.
Routed rows are recognized by the destination colon, or a `-` gateway followed
by a destination. For a legacy password beginning with route-shaped words, use
a `./` file reference to avoid ambiguity.

Gateway routes allocate `getport caller:alias` and ensure the loopback forward
with `ssh -O forward`. Enable connection sharing for the gateway: `ControlMaster
auto`, a `ControlPath`, and `ControlPersist`. With no master, SSH starts one with
`-fNT`, `ExitOnForwardFailure=yes` and keepalives (10 seconds, two missed probes).
Repeated calls reuse the forward. After a dead master exits, the next invocation
recreates it. Existing masters retain their own keepalive settings. There is no
background retry loop and service failures do not kill shared SSH sessions.
Changing an active route requires closing its old forward first; a conflicting
listener fails setup instead of silently directing traffic to the wrong target.

VNC receives `127.0.0.1::port`, RDP receives `127.0.0.1:port`, and SSH receives
`-p port -o HostKeyAlias=alias`. A `-` gateway connects directly. `xtv` and `rd`
pass credentials through the existing environment/stdin launcher, never viewer
arguments. SSH retains normal SSH authentication; its password field is not
injected. Other callers launched by bare aliases receive `host:port` as their
first argument and retain their own authentication behavior.

Interactive RDP stays in the foreground. Its password is fed first, then terminal
input remains available for certificate questions. Certificate decisions remain
interactive; closing the viewer also stops the terminal relay.

Manual `sshh` forwards and bare registry names remain supported. Without a route,
commands use a registered port, the existing numeric resolver, or a literal
destination. Unknown registry lookups never allocate.

Reload with `source ~/utils/aliases`.

### Stop listeners

```bash
lsofkill 3000 :8080
# SIGTERM 12345 python3
```

Accepts one or more ports, with optional `:` prefixes. It sends SIGTERM once per matching TCP listener process and prints its PID and process name only when signaling succeeds. SIGTERM requests termination; a process can handle or ignore it. With no listeners it produces no output. Other users' processes still require sufficient permissions.
