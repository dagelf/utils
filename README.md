# dagelf utils

Linux CLI helpers: bash aliases plus small scripts. Read anything before you run it.

    git clone --depth 1 https://github.com/dagelf/utils && utils/install.sh --system   # omit --system to keep your screen, ssh defaults unchanged
    utils/install.sh --uninstall                                                       # teardown

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
getport myapp               # allocate if new; otherwise check whether it is listening
getport --lookup myapp      # raw registry lookup, without checking or changing anything
port=$(getport)             # allocate a fresh port; print its generated name to stderr
```

Ports start at 10000; released ports are reused before allocating higher numbers. With no name, each call gets a fresh allocation named `<caller-basename>:<port>`, for example `deploy.sh:10001`. The caller is the parent command, or its script filename for common interpreters; interactive shells and `bash -c` use `bash`. The generated name goes to stderr as `getport: deploy.sh:10001`. Stdout contains only the number, so command substitution works.

For an existing name, `getport name` checks local TCP/UDP listeners with `ss`. A live allocation prints the port to stdout and a URL such as `tcp://127.0.0.1:10001` (or `udp://...`) to stderr. These URLs identify the transport; they do not assume the service is HTTP. If no listener remains, it deletes the allocation, makes the port reusable, prints nothing on either stream, and exits 1. Calling that now-absent name again allocates a port. A new allocation also has no listener until your application binds it, so checking it before then releases it too.

`getport --lookup name` is the read-only registry operation: it returns the stored number without probing or reclaiming it, or exits 1 silently if absent. The tunnel helpers use this during setup, before SSH can bind its ports. Other errors exit 2.

The registry lives at `${XDG_STATE_HOME:-$HOME/.local/state}/dagelf-utils/ports.sqlite3`. SQLite serializes concurrent allocations and enforces unique names and ports. New allocations skip ports already bound for TCP or UDP on IPv4 or IPv6. Allocations persist until checked and found closed; this is a registry, not an OS reservation, so unrelated programs can still claim an unused port. Liveness checks identify a listening port, not ownership of its process.

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

### Stop listeners

```bash
lsofkill 3000 :8080
# SIGTERM 12345 python3
```

Accepts one or more ports, with optional `:` prefixes. It sends SIGTERM once per matching TCP listener process and prints its PID and process name only when signaling succeeds. SIGTERM requests termination; a process can handle or ignore it. With no listeners it produces no output. Other users' processes still require sufficient permissions.
