#!/bin/sh
# todo: add support for non-debian and do only user install and make global install require a switch? 
cd "$(dirname -- "$0")" 2>/dev/null # allows script to be called from another directory

#todo ask to install globally, then just sudo cp to /usr/local/bin and tee /etc/screenrc
S=`which sudo`
echo -n "I am ";whoami|grep root && S=""
which wget >/dev/null || {
  I="$S apt-get install -y"
  $I wget
 }

if $S whoami; then 
echo Installing globally...
echo scripts
$S cp scripts/* /usr/local/bin
echo screenrc
grep -q '^termcapinfo xterm* ti@:te@' /etc/screenrc || echo 'termcapinfo xterm* ti@:te@'|$S tee -a /etc/screenrc
echo ssh_config
grep -q ControlPersist /etc/ssh/ssh_config || cat << EOF |$S tee -a /etc/ssh/ssh_config
	ControlMaster auto
	ControlPath ~/.ssh/sockets/%r@%h-%p
	ControlPersist 600
EOF
echo permissions and groups...
$S chgrp src /usr/src
$S chmod g+s /usr/src
$S usermod -a -G src `whoami` # add current user to src group
$S mkdir -p /usr/src/github # todo - make git pulls from github pull here under username
else 
echo Installing for `whoami` only...
mkdir ~/bin 2>/dev/null
cp scripts/* ~/bin 
echo screenrc
echo 'termcapinfo xterm* ti@:te@'|tee -a ~/.screenrc
echo Can\'t do permissions and groups without root
fi

scripts/defaults

echo Done\!
