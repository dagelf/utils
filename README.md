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
