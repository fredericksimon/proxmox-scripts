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

# Base raw github URL
_raw_base="https://raw.githubusercontent.com/fredericksimon/proxmox-scripts/main/wireguard"
           
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

runcmd 'apt-get update'
export DEBIAN_FRONTEND=noninteractive
runcmd 'apt-get install -y --no-install-recommends samba'
echo "---- Configuration de samba -----"
runcmd 'echo -e "[partage]\n\tcomment = partage video\n\tpath = /srv\n\tguest ok = no\n\tread only = no\n\tbrowseable = yes\n\tvalid users = @partage\n\tcreate mask = 0660\n\tdirectory mask = 0770\n\tforce group = partage" > /etc/samba/smb.conf'

echo "---- Création utilisateur et du groupe partage -----"
runcmd 'groupadd partage && useradd --group partage fred'
echo "---- Ajout du mot de passe à smb"
runcmd 'pass=emilie && (echo "$pass"; echo "$pass") | smbpasswd -s -a fred'

echo "---- création du partage et affectation des droits"
runcmd 'mkdir -p /srv && chgrp -R partage /srv && chmod -R g+rw /srv'
#runcmd 'systemctl --now enable smbd'

IP=$(hostname -I | cut -f1 -d ' ')
log "Installation complete"
