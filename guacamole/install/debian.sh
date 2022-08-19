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
MYSQL_GUACAMOLE_PW=ZpXmgkxrFEq3Xqdt

# Base raw github URL
_raw_base="https://raw.githubusercontent.com/fredericksimon/proxmox-scripts/main/guacamole"
           
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

apt-get update && apt install -y -q build-essential libcairo2-dev libjpeg62-turbo-dev libpng-dev libtool-bin uuid-dev libossp-uuid-dev libavcodec-dev libavformat-dev libavutil-dev libswscale-dev freerdp2-dev libpango1.0-dev libssh2-1-dev libtelnet-dev libvncserver-dev libwebsockets-dev libpulse-dev libssl-dev libvorbis-dev libwebp-dev tomcat9

log "Settings Tomacat 9 daemon"
# Start and enable tomcat9
systemctl enable --now tomcat9

log "Install guacamole server 1.4"

log "> Download guacamole server 1.4"
cd /tmp
wget https://dlcdn.apache.org/guacamole/1.4.0/source/guacamole-server-1.4.0.tar.gz
tar -xzf guacamole-server-1.4.0.tar.gz

log "> Change working directory"
cd guacamole-server-1.4.0/

log "> configure Guacamole server installation and verify system requirements"
./configure --with-systemd-dir=/etc/systemd/system/ --disable-dependency-tracking

log "> Compiling the source code"
make

log "> Make Guacamole server"
make install

log "> Update symbolic links of the system libraries"
ldconfig

log "> Reload the systemd manager, and apply the new systemd service (guacd)"
systemctl daemon-reload

log "> Start and enable guacd"
systemctl enable --now guacd

log "> Verify guacd"
systemctl status guacd

log "> Update Tomcat default path"
echo GUACAMOLE_HOME=/etc/guacamole >> /etc/default/tomcat9

log "> Create folder and conf file"
mkdir -p /etc/guacamole/{extensions,lib}
touch /etc/guacamole/{guacamole.properties,guacd.conf}

# ------- Mariadb -------
log "Install mariadb server"
cd /tmp

# Install mariadb server package
apt-get install mariadb-server -y

# MySQL/J connector
wget https://cdn.mysql.com//Downloads/Connector-J/mysql-connector-java_8.0.30-1debian11_all.deb
dpkg -i mysql-connector-java_8.0.30-1debian11_all.deb 
cp /usr/share/java/mysql-connector-java-8.0.30.jar /etc/guacamole/lib/

# Jdbc Auth connector
wget https://dlcdn.apache.org/guacamole/1.4.0/binary/guacamole-auth-jdbc-1.4.0.tar.gz
tar -xf guacamole-auth-jdbc-1.4.0.tar.gz
cd guacamole-auth-jdbc-1.4.0/mysql/
cp guacamole-auth-jdbc-mysql-1.4.0.jar /etc/guacamole/extensions/guacamole-auth-jdbc-mysql.jar

## Define MySQL root password
MYSQL_ROOT_PW=NBtp8z5VWIqTlktD
 
## Define MySQL lilac password
MYSQL_GUACAMOLE_PW=ZpXmgkxrFEq3Xqdt

#mysql -u root -pNBtp8z5VWIqTlktD
echo "CREATE DATABASE IF NOT EXISTS guacamole_db;" | mysql -u root

### Create lilac user with password
echo "grant index, drop, create, select, insert, update, delete, alter, lock tables on guacamole_db.* to 'guacamole_user'@'localhost' identified by '$MYSQL_GUACAMOLE_PW';" | mysql -u root

## Set MySQL root password in MySQL
echo "SET Password FOR 'root'@localhost = PASSWORD('$MYSQL_ROOT_PW') ; FLUSH PRIVILEGES;" | mysql -u root
   
mysql -u root -p$MYSQL_ROOT_PW guacamole_db < schema/001-create-schema.sql 
mysql -u root -p$MYSQL_ROOT_PW guacamole_db < schema/002-create-admin-user.sql 


echo -e "mysql-hostname: localhost\nmysql-port: 3306\nmysql-database: guacamole_db\nmysql-username: guacamole_user\nmysql-password: $MYSQL_GUACAMOLE_PW" | tee /etc/guacamole/guacamole.properties

echo -e "[server]\nbind_host = 0.0.0.0\nbind_port = 4822\n" | tee /etc/guacamole/guacd.conf

systemctl restart guacd
systemctl restart tomcat9

cd /tmp
wget --no-cache -O /var/lib/tomcat9/webapps/guacamole.war https://dlcdn.apache.org/guacamole/1.4.0/binary/guacamole-1.4.0.war 

# ------- Apache -------

apt-get -y install apache2

a2enmod proxy proxy_wstunnel proxy_http rewrite
            
echo -e "<VirtualHost *:80>\n    ServerName guacamole\n    ServerAlias guacamole\n    ErrorLog /var/log/apache2/example.io-error.log\n    CustomLog /var/log/apache2/example.io-access.log combined\n    <Location /guacamole/>\n        Order allow,deny\n        Allow from all\n        ProxyPass http://127.0.0.1:8080/guacamole/ flushpackets=on\n        ProxyPassReverse http://127.0.0.1:8080/guacamole/\n    </Location>\n    <Location /guacamole/websocket-tunnel>\n        Order allow,deny\n        Allow from all\n        ProxyPass ws://127.0.0.1:8080/guacamole/websocket-tunnel\n        ProxyPassReverse ws://127.0.0.1:8080/guacamole/websocket-tunnel\n    </Location>\n</VirtualHost>\n" | tee /etc/apache2/sites-available/guacamole.conf 

# activate guacamole.conf
a2ensite guacamole.conf

# verify apache2 configuration
apachectl configtest


sed '/^<\/Host>/i before=me' /etc/tomcat9/server.xml

sed -i 's,</Host>,<Valve className="org.apache.catalina.valves.RemoteIpValve" internalProxies="127.0.0.1" remoteIpHeader="x-forwarded-for"  remoteIpProxiesHeader="x-forwarded-by" protocolHeader="x-forwarded-proto" /></Host>,g' /etc/tomcat9/server.xml

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
