#!/bin/sh
# Setup:    ./install.sh            configure shell, screen and system defaults (needs root/sudo)
#           ./install.sh --user     only configure shell and personal screen defaults
# Teardown: ./install.sh --uninstall [--user]
set -e
D="$(cd "$(dirname -- "$0")" && pwd)"
TAG='# dagelf-utils'
S=; [ "$(id -u)" = 0 ] || S=sudo
SYS=1
case " $* " in *" --user "*) SYS= ;; esac
case " $* " in *" --uninstall "*) UN=1 ;; esac

screen_defaults () {
  cat <<'EOF'
# >>> dagelf-utils
termcapinfo xterm* ti@:te@
defscrollback 10000
startup_message off
hardstatus alwayslastline
hardstatus string '%{gk}[%{wk}%?%-Lw%?%{=b kR}(%{W}%n*%f %t%?(%u)%?%{=b kR})%{= w}%?%+Lw%?%? %{g}][%{d}%l%{g}][ %{= w}%Y/%m/%d %0C:%s%a%{g} ]%{W}'
# <<< dagelf-utils
EOF
}

# --- user: one line in ~/.bashrc --------------------------------------------
touch ~/.bashrc
sed -i "/$TAG\$/d" ~/.bashrc
[ -n "$UN" ] || echo "[ -r '$D/aliases' ] && . '$D/aliases' $TAG" >> ~/.bashrc
# legacy (pre-2026-10 installs copied a #defaults..#end-defaults block into ~/.bash_aliases)
[ -f ~/.bash_aliases ] && sed -i -e '/^#defaults/,/^#end-defaults/d' -e '/^#end-defaults/d' ~/.bash_aliases

# Screen defaults belong to the user too; preserve settings outside our block.
if [ -f ~/.screenrc ]; then
  sed -i '/^# >>> dagelf-utils/,/^# <<< dagelf-utils/d' ~/.screenrc
fi
[ -n "$UN" ] || screen_defaults >> ~/.screenrc

# --- system: drop-in files only, so teardown is just rm ---------------------
if [ -n "$SYS" ]; then
  F="/etc/sysctl.d/90-dagelf-utils.conf /etc/systemd/journald.conf.d/dagelf-utils.conf /etc/ssh/ssh_config.d/dagelf-utils.conf"
  $S sed -i '/^# >>> dagelf-utils/,/^# <<< dagelf-utils/d' /etc/screenrc 2>/dev/null || true
  if [ -n "$UN" ]; then
    $S rm -f $F
    $S systemctl disable --now earlyoom 2>/dev/null || true
  else
    $S mkdir -p /etc/systemd/journald.conf.d /etc/ssh/ssh_config.d
    echo 'kernel.sysrq=1' | $S tee /etc/sysctl.d/90-dagelf-utils.conf >/dev/null
    printf '[Journal]\nSystemMaxUse=50M\n' | $S tee /etc/systemd/journald.conf.d/dagelf-utils.conf >/dev/null
    printf 'Host *\n  ControlMaster auto\n  ControlPath ~/.ssh/socket-%%r@%%h-%%p\n  ControlPersist 600\n' | $S tee /etc/ssh/ssh_config.d/dagelf-utils.conf >/dev/null
    screen_defaults | $S tee -a /etc/screenrc >/dev/null
    $S sysctl -q -p /etc/sysctl.d/90-dagelf-utils.conf
    $S systemctl restart systemd-journald 2>/dev/null || true
    command -v earlyoom >/dev/null || { command -v pacman >/dev/null && $S pacman -S --noconfirm earlyoom || $S apt-get install -y earlyoom; }
    $S systemctl enable --now earlyoom 2>/dev/null || true
    $S groupadd -f src; $S chgrp src /usr/src; $S chmod g+s /usr/src; $S usermod -a -G src "$(id -un)"
    $S mkdir -p /usr/src/github
  fi
fi

echo "${UN:+un}installed. Open a new shell (or: . ~/.bashrc)"
