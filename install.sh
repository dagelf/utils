#!/bin/sh
# todo: add support for non-debian and do only user install and make global install require a switch? 
cd "$(dirname -- "$0")" 2>/dev/null # allows script to be called from another directory

#todo ask to install globally, then just sudo cp to /usr/local/bin and tee /etc/screenrc
S=`which sudo`
which wget >/dev/null || {
  I="$S apt-get install -y"
  $I wget
 }

if $S whoami; then 
echo Installing globally...
echo screenrc
grep -q '^termcapinfo xterm\* ti@:te@' /etc/screenrc
echo permissions and groups...
chgrp src /usr/src
chmod g+s /usr/src
usermod -a -G src `whoami` # add current user to src group
mkdir -p /usr/src/github # todo - make git pulls from github pull here under username
else 
echo Installing for `whoami` only...
mkdir ~/bin 2>/dev/null
cp scripts/* ~/bin 
echo screenrc
echo 'termcapinfo xterm\* ti@:te@'|tee -a ~/.screenrc
echo Can\'t do permissions and groups without root
fi

scripts/defaults

echo Done\!
