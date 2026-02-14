#!/usr/bin/env bash
# Show current key limits vs sane defaults, color-coded.
# Minimal deps: bash, tput or ANSI, standard tools.

# Color setup
if test -t 1; then
  R=$(printf '\033[31;43m')
#  R=$(printf '\033[31m')
  G=$(printf '\033[32m')
  Y=$(printf '\033[33m')
  B=$(printf '\033[34m')
  C=$(printf '\033[36m')
  N=$(printf '\033[0m')
else
  R=;G=;Y=;B=;C=;N=
fi

note() { printf "%b%s%b\n" "$C" "$1" "$N"; }
ok()   { printf "%b%s%b\n" "$G" "$1" "$N"; }
bad()  { printf "%b%s%b\n" "$R" "$1" "$N"; }
warn() { printf "%b%s%b\n" "$Y" "$1" "$N"; }

head_line() {
  printf "%b\n" "$1"
}

# Recommended baselines (tune if needed)
REC_SWAP_MAX_PCT=200          # swap <= 2x RAM
REC_SWAPPINESS=10
REC_VFS_CACHE_PRESSURE=100
REC_DIRTY_BG_RATIO=5
REC_DIRTY_RATIO=15

REC_DEFAULT_TASKSMAX=512
REC_USERTASKSMAX=256

REC_MIN_NOFILE_SOFT=65536
REC_MIN_NOFILE_HARD=1048576

REC_NPROC_HARD=4096

hr() { printf "%b%s%b\n" "$B" "------------------------------------------------------------" "$N"; }

# Helpers
get_sysctl() {
  sysctl -n "$1" 2>/dev/null || echo "NA"
}

# track bad vm.* for sysctl -w suggestions
FIX_CMDS=()

add_fix() {
  # $1 key, $2 value
  FIX_CMDS+=("sudo sysctl -w $1=$2")
}

check_range() {
  # $1 label, $2 current, $3 min, $4 max
  local label="$1" cur="$2" min="$3" max="$4"
  if [ "$cur" = "NA" ]; then
    warn "$label: NA"
    return
  fi
  if [ "$cur" -ge "$min" ] && [ "$cur" -le "$max" ]; then
    ok "$label: $cur (ok $min-$max)"
  else
    bad "$label: $cur (want $min-$max)"
  fi
}

compare_eq_vm() {
  # for vm.*: label/key, current, wanted
  local key="$1" cur="$2" want="$3"
  if [ "$cur" = "NA" ]; then
    warn "$key: NA"
    return
  fi
  if [ "$cur" -eq "$want" ] 2>/dev/null; then
    ok "$key: $cur"
  else
    bad "$key: $cur (want $want)"
    add_fix "$key" "$want"
  fi
}

compare_eq() {
  # $1 label, $2 current, $3 wanted
  local label="$1" cur="$2" want="$3"
  if [ "$cur" = "NA" ]; then
    warn "$label: NA"
    return
  fi
  if [ "$cur" -eq "$want" ]; then
    ok "$label: $cur"
  else
    bad "$label: $cur (want $want)"
  fi
}

compare_min() {
  # $1 label, $2 current, $3 min
  local label="$1" cur="$2" min="$3"
  if [ "$cur" = "NA" ]; then
    warn "$label: NA"
    return
  fi
  if [ "$cur" -ge "$min" ]; then
    ok "$label: $cur (>= $min)"
  else
    bad "$label: $cur (< $min)"
  fi
}

compare_max() {
  # $1 label, $2 current, $3 max
  local label="$1" cur="$2" max="$3"
  if [ "$cur" = "NA" ]; then
    warn "$label: NA"
    return
  fi
  if [ "$cur" -le "$max" ]; then
    ok "$label: $cur (<= $max)"
  else
    bad "$label: $cur (> $max)"
  fi
}

hr
head_line "SYSTEM MEMORY AND SWAP"

mem_total_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
swap_total_kb=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo 2>/dev/null)
if [ -z "$mem_total_kb" ]; then
  warn "Unable to read /proc/meminfo"
else
  mem_gb=$((mem_total_kb / 1024 / 1024))
  swap_gb=$((swap_total_kb / 1024 / 1024))
  printf "RAM: %s GiB\n" "${mem_gb}"
  printf "Swap: %s GiB\n" "${swap_gb}"

  if [ "$mem_total_kb" -gt 0 ]; then
    swap_pct=$(( swap_total_kb * 100 / mem_total_kb ))
    if [ "$swap_pct" -le "$REC_SWAP_MAX_PCT" ]; then
      ok "Swap/RAM ratio: ${swap_pct}%% (<= ${REC_SWAP_MAX_PCT}%%)"
    else
      bad "Swap/RAM ratio: ${swap_pct}%% (> ${REC_SWAP_MAX_PCT}%%)"
    fi
  fi
fi

swappiness=$(get_sysctl vm.swappiness)
compare_eq_vm "vm.swappiness" "$swappiness" "$REC_SWAPPINESS"

vfs_cache_pressure=$(get_sysctl vm.vfs_cache_pressure)
compare_eq_vm "vm.vfs_cache_pressure" "$vfs_cache_pressure" "$REC_VFS_CACHE_PRESSURE"

dbgr=$(get_sysctl vm.dirty_background_ratio)
compare_eq_vm "vm.dirty_background_ratio" "$dbgr" "$REC_DIRTY_BG_RATIO"

dr=$(get_sysctl vm.dirty_ratio)
compare_eq_vm "vm.dirty_ratio" "$dr" "$REC_DIRTY_RATIO"

oom_kill_alloc=$(get_sysctl vm.oom_kill_allocating_task)
if [ "$oom_kill_alloc" = "1" ]; then
  ok "vm.oom_kill_allocating_task: 1"
else
  bad "vm.oom_kill_allocating_task: $oom_kill_alloc (want 1)"
  add_fix "vm.oom_kill_allocating_task" "1"
fi

panic_on_oom=$(get_sysctl vm.panic_on_oom)
if [ "$panic_on_oom" = "0" ]; then
  ok "vm.panic_on_oom: 0"
else
  bad "vm.panic_on_oom: $panic_on_oom (want 0)"
  add_fix "vm.panic_on_oom" "0"
fi

hr
head_line "SYSTEMD GLOBAL LIMITS"

# systemd system.conf defaults
if command -v systemctl >/dev/null 2>&1; then
  sys_DefaultTasksMax=$(systemctl show -p DefaultTasksMax --value 2>/dev/null)
  sys_DefaultTasksMax=${sys_DefaultTasksMax:-"NA"}
  if [ "$sys_DefaultTasksMax" != "NA" ] && [ "$sys_DefaultTasksMax" != "infinity" ]; then
    compare_eq "systemd DefaultTasksMax" "$sys_DefaultTasksMax" "$REC_DEFAULT_TASKSMAX"
  else
    bad "systemd DefaultTasksMax: $sys_DefaultTasksMax (want finite like $REC_DEFAULT_TASKSMAX)"
  fi

  # logind UserTasksMax
  userTasksMax="NA"
  if systemctl show -p UserTasksMax user-0.slice >/dev/null 2>&1; then
    userTasksMax=$(systemctl show -p TasksMax user-0.slice --value 2>/dev/null)
  else
    # fallback: parse logind.conf if present
    if [ -f /etc/systemd/logind.conf ]; then
      userTasksMax=$(awk -F= '/^\s*UserTasksMax=/ {gsub(/[ \t]/,"",$2);print $2}' /etc/systemd/logind.conf)
      [ -z "$userTasksMax" ] && userTasksMax="NA"
    fi
  fi
  if [ "$userTasksMax" = "NA" ] || [ "$userTasksMax" = "infinity" ] || [ "$userTasksMax" -gt "$REC_USERTASKSMAX" ] 2>/dev/null; then
    bad "UserTasksMax: $userTasksMax (want <= $REC_USERTASKSMAX)"
  else
    ok "UserTasksMax: $userTasksMax"
  fi
else
  warn "systemd not detected; skipping systemd limits"
fi

hr
head_line "THIS SHELL ULIMITS (REPRESENTATIVE)"

nofile_soft=$(ulimit -Sn 2>/dev/null)
nofile_hard=$(ulimit -Hn 2>/dev/null)
nproc_soft=$(ulimit -Su 2>/dev/null)
nproc_hard=$(ulimit -Hu 2>/dev/null)

compare_min "nofile (soft)" "$nofile_soft" "$REC_MIN_NOFILE_SOFT"
compare_min "nofile (hard)" "$nofile_hard" "$REC_MIN_NOFILE_HARD"

if [ "$nproc_hard" != "unlimited" ] && [ "$nproc_hard" != "NA" ]; then
  compare_eq "nproc (hard)" "$nproc_hard" "$REC_NPROC_HARD"
else
  # For root often unlimited; treat unlimited as warn.
  if [ "$EUID" -eq 0 ]; then
    warn "nproc (hard): $nproc_hard (ok for root, use per-user limits)"
  else
    bad "nproc (hard): $nproc_hard (want <= $REC_NPROC_HARD)"
  fi
fi

if [ "$nproc_soft" != "unlimited" ] && [ "$nproc_soft" != "NA" ]; then
  if [ "$nproc_soft" -le "$REC_NPROC_HARD" ] 2>/dev/null; then
    ok "nproc (soft): $nproc_soft (<= $REC_NPROC_HARD)"
  else
    bad "nproc (soft): $nproc_soft (> $REC_NPROC_HARD)"
  fi
else
  if [ "$EUID" -eq 0 ]; then
    warn "nproc (soft): $nproc_soft (root)"
  else
    bad "nproc (soft): $nproc_soft (set per-user limit)"
  fi
fi

hr
head_line "OOM DAEMON (RECOMMENDED)"

earlyoom_status="NA"
systemd_oomd_status="NA"

if command -v systemctl >/dev/null 2>&1; then
  earlyoom_status=$(systemctl is-active earlyoom 2>/dev/null || echo "inactive")
  systemd_oomd_status=$(systemctl is-active systemd-oomd 2>/dev/null || echo "inactive")
else
  earlyoom_status="inactive"
  systemd_oomd_status="inactive"
fi

if [ "$earlyoom_status" = "active" ]; then
  ok "earlyoom: active"
else
  warn "earlyoom: $earlyoom_status (recommend active OR systemd-oomd)"
fi

if [ "$systemd_oomd_status" = "active" ]; then
  ok "systemd-oomd: active"
else
  warn "systemd-oomd: $systemd_oomd_status (ok if earlyoom covers)"
fi

hr
note "Green = aligned with conservative safe defaults."
note "Red = change suggested to reduce risk of load / OOM death spirals."

hr
if [ "${#FIX_CMDS[@]}" -gt 0 ]; then
  head_line "SUGGESTED TEMPORARY FIXES (COPY/PASTE)"
  for cmd in "${FIX_CMDS[@]}"; do
    printf "%b%s%b\n" "$R" "$cmd" "$N"
  done
  note "Persist via /etc/sysctl.d/99-tuning.conf then: sudo sysctl --system"
else
  ok "All checked vm.* values match recommended defaults."
fi
