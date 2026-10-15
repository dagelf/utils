# AGENTS.md

Personal Linux CLI utils. Keep it lean: no build, no deps, no generated files.

## Layout
- `aliases` — bash aliases/functions. Sourced **in place** from `~/.bashrc`; also puts `scripts/` on PATH. Nothing machine-specific.
- `scripts/` — tools too long for a one-liner: one executable each, with a shebang, `chmod +x`. Anything that fits on a line goes in `aliases` instead.
- In `aliases`, define functions as `function name () {...}`. The `function` keyword stops an existing alias of the same name from breaking parsing.
- `install.sh` — setup and teardown (`--uninstall`, `--system`). Idempotent. System changes are drop-in files only.
- `snippets` — notes, not executed. `unixtime2human` — pipe anything with unix timestamps through it for wall-clock times.

The repo is public. Never commit hostnames, IPs, usernames, key paths or anything machine-specific; that stays in `~/.bash_aliases`. Secrets are referenced by env var only (`OPENROUTER_KEY_FILE`, `NVIDIA_KEY_FILE`, `NVIDIA_BASEURL_FILE`, `HF_KEY_FILE`, `HF_BIN`), set in `~/.bashrc`.

## Commands
    ./install.sh                     # setup (user): one tagged line in ~/.bashrc
    ./install.sh --system            # + sysctl, journald, ssh, screen, earlyoom, src group
    ./install.sh --uninstall         # teardown (user)
    ./install.sh --uninstall --system
    bash -n aliases install.sh       # syntax check before every commit

## Reconciling pushes from old copies
Copies cloned before the 2026-10 rewrite have the old layout (`defaults`, `scripts/defaults`, `#defaults` markers and machine vars inside `aliases`, scripts copied to `/usr/local/bin`). To take their work in:

    git fetch <remote-or-path> && git merge --no-commit <ref>     # or: git pull --no-commit
    git status --short                                            # list conflicts

Resolve each, then `bash -n aliases install.sh`, `git commit`:

| Old path | Action |
|---|---|
| `aliases` | Keep new structure. Port genuinely new aliases/functions into the matching section. Drop `#defaults`/`#end-defaults` lines, machine vars (`WLAN=`, `ETH=`, `RES=`, `WIN_*`, `GIT_*`, `SERVERS=`), and duplicates. |
| `defaults`, `scripts/defaults`, `scripts/us.sh` | `git rm`. Port any new system tweak into `install.sh` as a drop-in file with a matching `--uninstall` line. |
| `scripts/<new or changed>` | Keep. Ensure shebang + `chmod +x`. If it's a one-liner, make it a function in `aliases` instead. |
| `scripts/{1l,dmy,march,pty,glibc,fingerprints,pythons,findlibwith,matchn,waitall,mrec,mplay,md,rbench,smartlog,clean,ww,dxr,dip,sk,github-new,nct,nctty}` | Now functions or aliases of the same name in `aliases`. Port the change there, then `git rm` the script. |
| `scripts/{ob,ob1,ob_helper*,dockerfile,makedev1,memd1,memd2,pactl-sinkdefault.sh,lmsyschat,xmacro.ini}`, `incoming/` | Deliberately removed. `git rm` unless the old copy made a real improvement — then restore it under `scripts/`. |
| `install.sh` | Keep new. Port intent only, never the copy-to-`/usr/local/bin` or `~/.bash_aliases` block approach. |

Shortcut for a modify/delete conflict on a removed file: `git rm <path>`.

On the old machine afterwards: `git pull && ./install.sh` once. It removes the legacy `#defaults` block from `~/.bash_aliases`. Stale copies in `/usr/local/bin` are harmless: `scripts/` is prepended to PATH, so the repo versions win.
