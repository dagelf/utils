#!/usr/bin/env bash
set -euo pipefail

ACTION="install"
BASHRC_PATH="${BASHRC_PATH:-$HOME/.bashrc}"
LAN_PREFIX="${LAN_PREFIX:-192.168}"
DEFAULT_THIRD_OCTET="${DEFAULT_THIRD_OCTET:-2}"

MARK_BEGIN="# >>> lan-ssh-shortcut >>>"
MARK_END="# <<< lan-ssh-shortcut <<<"

usage() {
  cat <<'USAGE'
Usage:
  install_lan_ssh_shortcut.sh [--install|--uninstall] [options]

Options:
  --install                 Install shortcut block (default action)
  --uninstall               Remove shortcut block
  --bashrc <path>           Target bashrc file (default: ~/.bashrc)
  --prefix <a.b>            First two octets to use (default: 192.168)
  --default-third <n>       Third octet when shorthand is just "47" (default: 2)
  -h, --help                Show this help

Environment variable overrides:
  BASHRC_PATH, LAN_PREFIX, DEFAULT_THIRD_OCTET
USAGE
}

die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

validate_octet() {
  local value="$1"
  [[ "$value" =~ ^[0-9]{1,3}$ ]] || return 1
  (( value >= 0 && value <= 255 ))
}

validate_prefix() {
  local prefix="$1"
  local a b
  [[ "$prefix" =~ ^([0-9]{1,3})\.([0-9]{1,3})$ ]] || return 1
  a="${BASH_REMATCH[1]}"
  b="${BASH_REMATCH[2]}"
  validate_octet "$a" && validate_octet "$b"
}

strip_marked_block() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"

  awk -v begin="$MARK_BEGIN" -v end="$MARK_END" '
    $0 == begin { skip = 1; next }
    $0 == end   { skip = 0; next }
    !skip { print }
  ' "$file" >"$tmp"

  mv "$tmp" "$file"
}

append_block() {
  local file="$1"
  local p1 p2
  p1="${LAN_PREFIX%%.*}"
  p2="${LAN_PREFIX##*.}"

  cat >>"$file" <<EOF
$MARK_BEGIN
# Numeric SSH shortcut:
#   47    -> ${p1}.${p2}.${DEFAULT_THIRD_OCTET}.47
#   2.47  -> ${p1}.${p2}.2.47
#
# Behavior:
# - Triggers only when an unknown command is numeric shorthand.
# - Pings target once before attempting SSH.
# - For dotted shorthand (for example 2.47), if /etc/hosts contains a hostname
#   for that IP, it SSHes to that hostname.
# - Falls back to prior command_not_found_handle if one existed.

__lan_ssh_prefix_a="${p1}"
__lan_ssh_prefix_b="${p2}"
__lan_ssh_default_third_octet="${DEFAULT_THIRD_OCTET}"

__lan_ssh_target_from_token() {
  local token="\$1"
  local third fourth

  if [[ "\$token" =~ ^([0-9]{1,3})$ ]]; then
    third="\$__lan_ssh_default_third_octet"
    fourth="\${BASH_REMATCH[1]}"
  elif [[ "\$token" =~ ^([0-9]{1,3})\\.([0-9]{1,3})$ ]]; then
    third="\${BASH_REMATCH[1]}"
    fourth="\${BASH_REMATCH[2]}"
  else
    return 126
  fi

  if (( third < 0 || third > 255 || fourth < 0 || fourth > 255 )); then
    return 126
  fi

  printf '%s.%s.%s.%s\n' "\$__lan_ssh_prefix_a" "\$__lan_ssh_prefix_b" "\$third" "\$fourth"
}

__lan_ssh_host_for_ip() {
  local ip="\$1"
  awk -v ip="\$ip" '
    /^[[:space:]]*#/ || NF < 2 { next }
    \$1 == ip {
      for (i = 2; i <= NF; i++) {
        if (\$i !~ /^#/) { print \$i; exit }
      }
    }
  ' /etc/hosts
}

__lan_ssh_option_takes_arg() {
  case "\$1" in
    -B|-b|-c|-D|-E|-e|-F|-I|-i|-J|-L|-l|-m|-O|-o|-p|-Q|-R|-S|-W|-w) return 0 ;;
    *) return 1 ;;
  esac
}

__lan_ssh_exec() {
  local target="\$1"
  shift || true

  local -a ssh_opts=()
  while [[ \$# -gt 0 ]]; do
    if [[ "\$1" == "--" ]]; then
      shift
      break
    fi

    if [[ "\$1" != -* ]]; then
      break
    fi

    ssh_opts+=("\$1")
    if __lan_ssh_option_takes_arg "\$1" && [[ \$# -ge 2 ]]; then
      ssh_opts+=("\$2")
      shift
    fi
    shift
  done

  ssh "\${ssh_opts[@]}" "\$target" "\$@"
}

__lan_ssh_handle_token() {
  local token="\$1"
  shift || true

  local ip
  ip="\$(__lan_ssh_target_from_token "\$token")" || return 126

  if ! ping -c 1 -W 1 "\$ip" >/dev/null 2>&1; then
    printf 'Host unreachable: %s\n' "\$ip" >&2
    return 127
  fi

  local target="\$ip"
  if [[ "\$token" == *.* ]]; then
    local host
    host="\$(__lan_ssh_host_for_ip "\$ip")"
    if [[ -n "\$host" ]]; then
      target="\$host"
    fi
  fi

  __lan_ssh_exec "\$target" "\$@"
}

if declare -F command_not_found_handle >/dev/null && ! declare -F __lan_ssh_orig_command_not_found_handle >/dev/null; then
  eval "\$(declare -f command_not_found_handle | sed '1s/command_not_found_handle/__lan_ssh_orig_command_not_found_handle/')"
fi

command_not_found_handle() {
  local token="\$1"
  shift || true

  __lan_ssh_handle_token "\$token" "\$@"
  local rc="\$?"

  if [[ "\$rc" -eq 126 ]]; then
    if declare -F __lan_ssh_orig_command_not_found_handle >/dev/null; then
      __lan_ssh_orig_command_not_found_handle "\$token" "\$@"
      return \$?
    fi
    printf 'bash: %s: command not found\n' "\$token" >&2
    return 127
  fi

  return "\$rc"
}
$MARK_END
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      ACTION="install"
      ;;
    --uninstall)
      ACTION="uninstall"
      ;;
    --bashrc)
      shift
      [[ $# -gt 0 ]] || die "--bashrc requires a path"
      BASHRC_PATH="$1"
      ;;
    --prefix)
      shift
      [[ $# -gt 0 ]] || die "--prefix requires a value (a.b)"
      LAN_PREFIX="$1"
      ;;
    --default-third)
      shift
      [[ $# -gt 0 ]] || die "--default-third requires a value (0-255)"
      DEFAULT_THIRD_OCTET="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "Unknown argument: $1"
      ;;
  esac
  shift
done

validate_prefix "$LAN_PREFIX" || die "Invalid --prefix value: $LAN_PREFIX (expected a.b with each octet 0-255)"
validate_octet "$DEFAULT_THIRD_OCTET" || die "Invalid --default-third value: $DEFAULT_THIRD_OCTET (expected 0-255)"

mkdir -p "$(dirname "$BASHRC_PATH")"
touch "$BASHRC_PATH"

strip_marked_block "$BASHRC_PATH"

if [[ "$ACTION" == "install" ]]; then
  append_block "$BASHRC_PATH"
  printf 'Installed LAN SSH shortcut in %s\n' "$BASHRC_PATH"
else
  printf 'Uninstalled LAN SSH shortcut from %s\n' "$BASHRC_PATH"
fi

printf 'Reload shell with: source %s\n' "$BASHRC_PATH"
