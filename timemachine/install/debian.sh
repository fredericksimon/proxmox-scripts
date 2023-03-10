#!/usr/bin/env bash
set -euo pipefail
trap trapexit EXIT SIGTERM

DISTRO_ID=$(cat /etc/*-release | grep -w ID | cut -d= -f2 | tr -d '"')
DISTRO_CODENAME=$(cat /etc/*-release | grep -w VERSION_CODENAME | cut -d= -f2 | tr -d '"')

TEMPDIR=$(mktemp -d)
TEMPLOG="$TEMPDIR/tmplog"
TEMPERR="$TEMPDIR/tmperr"
LASTCMD=""
WGETOPT="-t 1 -T 15 -q"
DEVDEPS="git build-essential libffi-dev libssl-dev python3-dev"

## Define MySQL root password
MYSQL_ROOT_PW=NBtp8z5VWIqTlktD
 
## Define MySQL lilac password
MYSQL_timemachine_PW=ZpXmgkxrFEq3Xqdt

# Base raw github URL
_raw_base="https://raw.githubusercontent.com/fredericksimon/proxmox-scripts/main/timemachine"
           
cd $TEMPDIR
touch $TEMPLOG

# Helpers
log() { 
  logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g");
  clear && printf "\033c\e[3J$logs\n\e[34m[info] $*\e[0m\n" | tee $TEMPLOG;
}
runcmd() { 
  LASTCMD=$(grep -n "$*" "$0" | sed "s/[[:blank:]]*runcmd//");
  if [[ "$#" -eq 1 ]]; then
    eval "$@" 2>$TEMPERR;
  else
    $@ 2>$TEMPERR;
  fi
}
trapexit() {
  status=$?
  
  if [[ $status -eq 0 ]]; then
    logs=$(cat $TEMPLOG | sed -e "s/34/32/g" | sed -e "s/info/success/g")
    clear && printf "\033c\e[3J$logs\n";
  elif [[ -s $TEMPERR ]]; then
    logs=$(cat $TEMPLOG | sed -e "s/34/31/g" | sed -e "s/info/error/g")
    err=$(cat $TEMPERR | sed $'s,\x1b\\[[0-9;]*[a-zA-Z],,g' | rev | cut -d':' -f1 | rev | cut -d' ' -f2-) 
    clear && printf "\033c\e[3J$logs\e[33m\n$0: line $LASTCMD\n\e[33;2;3m$err\e[0m\n"
  else
    printf "\e[33muncaught error occurred\n\e[0m"
  fi
  
  # Cleanup
  apt-get remove --purge -y $DEVDEPS -qq &>/dev/null
  apt-get autoremove -y -qq &>/dev/null
  apt-get clean
  rm -rf $TEMPDIR
  rm -rf /root/.cache
}


# Install dependencies
log "Installing dependencies"

echo "LC_ALL=en_US.UTF-8" >> /etc/environment
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
locale-gen en_US.UTF-8

export DEBIAN_FRONTEND=noninteractive

apt-get update && apt install -y -q samba

log "Settings Samba 4 daemon"
# Start and enable tomcat9
systemctl enable --now smbd

log "Install timemachine server 1.4"

echo -e "[Timemachine]\n    comment = Time Machine\n    path = /srv/timemachine\n    browseable = yes\n
    writeable = yes\n    create mask = 0600\n    directory mask = 0700\n    spotlight = yes\n    vfs objects = catia fruit streams_xattr\n    fruit:aapl = yes\n    fruit:time machine = yes\n    fruit:resource = xattr" | tee /etc/samba/smb.conf

mkdir -p /srv/timemachine

adduser fred
echo -e "emilie\nemilie" | (smbpasswd -s fred)
echo -e "emilie\nemilie" | (passwd --stdin fred)


# Restart tomcat9
systemctl restart smbd

IP=$(hostname -I | cut -f1 -d ' ')
log "Installation complete"
