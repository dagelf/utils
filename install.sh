#!/bin/sh
# todo: add support for non-debian
cd "$(dirname -- "$0")" 2>/dev/null # allows script to be called from another directory

S=`which sudo`
which wget >/dev/null || {
  I="$S apt-get install -y"
  $I wget
 }
$S cp scripts/* /usr/local/bin || echo "Please run with sudo or as root."

echo Done\!
