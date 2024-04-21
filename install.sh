#!/bin/sh
# todo: add support for non-debian and do only user install and make global install require a switch? 
cd "$(dirname -- "$0")" 2>/dev/null # allows script to be called from another directory

# then just sudo cp to /usr/local/bin and tee /etc/screenrc
S=false
echo -n "Install as root? (Y/n) "; read a; [ "$a" != "n" ] && [ "$a" != "N" ] && S=`which sudo`
if whoami|grep root&&S="" >/dev/null || ($S whoami) >/dev/null; then # don't need sudo if we are root, else check if sudo exists
echo Installing globally...
which wget >/dev/null || {
  echo Installing wget...
  I="$S apt-get install -y"
  $I wget 
 }
which earlyoom >/dev/null || {
  echo Installing earlyoom...
  I="$S apt-get install -y"
  $I earlyoom
 }
# todo copy from defaults or make more modular
grep -q ^kernel.sysrq=1 /etc/sysctl.conf /etc/sysctl.d/*|| echo "kernel.sysrq=1" | $S tee -a /etc/sysctl.conf
echo Trimming systemd journal...
$S journalctl --vacuum-size=50M
$S cp scripts/* /usr/local/bin # fixme move more to aliases, also clean up old utils still scattered on various machines?
f=/etc/screenrc; echo $f # enable mouse wheel scroll in screen
grep -q '^termcapinfo xterm* ti@:te@' $f || echo 'termcapinfo xterm* ti@:te@'|$S tee -a $f
f=/etc/ssh/ssh_config; echo $f # enable socket reuse
if ! grep -q ControlPersist $f; then 
cat <<EOF | $S tee -a $f
	ControlMaster auto
	ControlPath ~/.ssh/socket-%r@%h-%p
	ControlPersist 600
EOF
fi
$S chgrp src /usr/src
$S chmod g+s /usr/src
$S usermod -a -G src `whoami` # add current user to src group
$S mkdir -p /usr/src/github # todo - make git pulls from github pull here under username
else 
echo Installing for `whoami` only... you\'re missing out\!
mkdir ~/bin 2>/dev/null
cp scripts/* ~/bin 
echo Enable mouse scrolling in screenrc...
echo 'termcapinfo xterm* ti@:te@'|tee -a ~/.screenrc
echo Can\'t do permissions and groups without root
fi

./defaults

echo Done\!
