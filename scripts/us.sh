passwd
adduser coenraad
sed s@main@main\ universe@g -i /etc/apt/sources.list
apt update
apt -y install xserver-xorg wmaker firefox openssh-server x11vnc xtightvncviewer rdesktop git slock stterm pwgen
export DISPLAY=:0
mkdir -p /usr/src/github/dagelf
cd /usr/src/github/dagelf
git clone https://github.com/dagelf/utils --depth=1
utils/install.sh
RES=1280x1024 WIN_USER="Administrator" WIN_PASS="-" GIT_USER="dagelf" GIT_EMAIL="coenraad@wish.org.za" scripts/defaults
source /root/.bash_aliases
Xorg  & sleep 3; stterm & wmaker &
