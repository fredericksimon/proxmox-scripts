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
_raw_base="https://raw.githubusercontent.com/fredericksimon/proxmox-scripts/main/repo"
           
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
export repo_FRONTEND=noninteractive

# # On configure wireguard

# Update the apt package index and install packages to allow apt to use a repository over HTTPS:
apt-get update -y --allow-releaseinfo-change
apt-get -y install apache2 apt-mirror

mkdir -p /var/www/html/debian

chown www-data:www-data /var/www/html/debian
#chown -R apt-mirror /media/$USER/Depots/miroir/{mirror,skel,var}

cp /etc/apt/mirror.list /etc/apt/mirror.list-bak

#set up the repository:
#echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/repo $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

mkdir -p /var/www/html/debian/var
cp /var/spool/apt-mirror/var/postmirror.sh /var/www/html/debian/var

echo -n "0 13	* * *	apt-mirror	/usr/bin/apt-mirror /etc/apt/mirror.list > /var/spool/apt-mirror/var/cron.log" >> /etc/cron.d/apt-mirror

"# set base_path    /var/spool/apt-mirror" en "set base_path    /var/www/html/debian"
wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
mkdir -p /var/www/html/elastic
chown www-data:www-data /var/www/html/*

mkdir -p /var/www/html/elastic/var
cp /var/spool/apt-mirror/var/postmirror.sh /var/www/html/elastic/var

/usr/bin/apt-mirror /etc/apt/elastic.list

# log "Setting up wiregard enviroment"
# _wg_server_private=`wg genkey`
# log "Clé privée : $_wg_server_private"
# _wg_server_public=`echo "$_wg_server_private" | wg pubkey`
# log "Clé public : $_wg_server_public"

# # Récupération des fichiers de configuration
# wget --no-cache -P /etc/wireguard $_raw_base/install/wg0.conf
# sed -i 's,<server-privatekey>,'"$_wg_server_private"',g' /etc/wireguard/wg0.conf

# wget --no-cache -P /etc/wireguard $_raw_base/install/server-key
# sed -i 's,<server-privatekey>,'"$_wg_server_private"',g' /etc/wireguard/server-key
# sed -i 's,<server-publickey>,'"$_wg_server_public"',g' /etc/wireguard/server-key


# chown -R root:root /etc/wireguard
# chmod -R og-rwx /etc/wireguard
# systemctl enable wg-quick@wg0.service
# systemctl start wg-quick@wg0.service

IP=$(hostname -I | cut -f1 -d ' ')
log "Installation complete"
