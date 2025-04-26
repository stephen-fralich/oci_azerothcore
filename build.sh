### Create instance perms
### Create tag namespace acore with realm sub key static
### Create dynamic group for instances 
#### tag.acore.realm.value='AzerothCore'
### Create policy allowing read of network load balancer info
#### Allow dynamic-group 'Default'/'all-instances' to read network-load-balancers in tenancy
#### Create policy to allow full access to object stores
### Create network
### Create reserved public IP address
### Create network security group to allow in ssh, authserver, worldserver, maybe SOAP for testing
###   Optional CIDR filter on ports
### Create object storage
### Create instance config
### Create instance pool
### Create network load balancer
## Read my acorerealm tag value
AZCORE_REALM=`oci-metadata -j | jq -Mr '.instance.definedTags.acore.realm'`
AZCORE_TEMP=`mktemp -d -p /dev/shm`
cd ${AZCORE_TEMP}
systemctl stop firewalld
systemctl disable firewalld
dnf update -y
curl -LO --retry 10 https://dev.mysql.com/get/mysql84-community-release-el9-1.noarch.rpm
dnf install -y ./mysql84-community-release-el9-1.noarch.rpm 
dnf install -y mysql-community-client mysql-community-client-plugins mysql-community-devel mysql-community-server
dnf install -y boost boost-devel readline-devel git cmake make gcc g++ clang oraclelinux-developer-release-el9 python39-oci-cli python3-pip tmux
pip install -q scrape-cli
useradd -U -m --system acore
## Configure mysql binding and innodb memory and socket files and auto-auth for root
echo "bind-address = 127.0.0.1" >> /etc/my.cnf
echo "mysqlx_bind_address = 127.0.0.1" >> /etc/my.cnf
echo "innodb_buffer_pool_size = 1024M" >> /etc/my.cnf
systemctl start mysqld
systemctl enable mysqld
ROOT_MYSQL=`openssl rand -base64 32 | tr '/' '_'`
AZCORE_MYSQL=`openssl rand -base64 32 | tr '/' '_'`
## Reset root mysql password
mysqladmin -u root --password=`grep 'A temporary password is generated for root' /var/log/mysqld.log | awk -F': ' '{print $2}'` password "${ROOT_MYSQL}"
echo "${ROOT_MYSQL}" > /root/mysqlrootpass
echo "${AZCORE_MYSQL}" > /root/mysqlacorepass
## Create acore user with acore sql file with random password
### https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/refs/heads/master/data/sql/create/create_mysql.sql
curl -LO --retry 10 https://raw.githubusercontent.com/azerothcore/azerothcore-wotlk/refs/heads/master/data/sql/create/create_mysql.sql
sed -i "s/CREATE USER 'acore'@'localhost' IDENTIFIED BY 'acore'/CREATE USER 'acore'@'localhost' IDENTIFIED BY '${AZCORE_MYSQL}'/" create_mysql.sql
mysql --password="$ROOT_MYSQL" < create_mysql.sql
## Setup instance principal auth
export OCI_CLI_AUTH=instance_principal
export OCI_CID=`oci-compartmentid`
## Restore database contents if in object store
### Restore acore_characters and acore_auth
## Alternately restore software from object store
git clone https://github.com/azerothcore/azerothcore-wotlk.git --branch master --single-branch /home/acore/azerothcore
mkdir build
cd build/
cmake /home/acore/azerothcore -DCMAKE_INSTALL_PREFIX=/home/acore/azeroth-server -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DWITH_WARNINGS=1 -DTOOLS=1 -DSCRIPTS=static -DCMAKE_BUILD_TYPE=Release
make -j 4 
make install
cd ..
## sub in new acore password and update authserver and worldserver configs and save
cp /home/acore/azeroth-server/etc/authserver.conf.dist /home/acore/azeroth-server/etc/authserver.conf
sed -i "s/^LoginDatabaseInfo.*= .*/LoginDatabaseInfo = \".\;\/var\/lib\/mysql\/mysql.sock\;acore\;${AZCORE_MYSQL}\;acore_auth\"/" /home/acore/azeroth-server/etc/authserver.conf
cp /home/acore/azeroth-server/etc/worldserver.conf.dist /home/acore/azeroth-server/etc/worldserver.conf
sed -i "s/^LoginDatabaseInfo.* = .*/LoginDatabaseInfo = \".\;\/var\/lib\/mysql\/mysql.sock\;acore\;${AZCORE_MYSQL}\;acore_auth\"/" /home/acore/azeroth-server/etc/worldserver.conf
sed -i "s/^WorldDatabaseInfo.* = .*/WorldDatabaseInfo = \".\;\/var\/lib\/mysql\/mysql.sock\;acore\;${AZCORE_MYSQL}\;acore_world\"/" /home/acore/azeroth-server/etc/worldserver.conf
sed -i "s/^CharacterDatabaseInfo.* = .*/CharacterDatabaseInfo = \".\;\/var\/lib\/mysql\/mysql.sock\;acore\;${AZCORE_MYSQL}\;acore_characters\"/" /home/acore/azeroth-server/etc/worldserver.conf
## create .service files for authserver and worldserver
tee /etc/systemd/system/worldserver.service << EOSF
[Unit]
Description=AzerothCore worldserver
After=network.target nss-lookup.target time-sync.target remote-fs.target mysqld.service authserver.service
Requires=mysqld.service authserver.service

[Service]
Type=forking
WorkingDirectory=/home/acore
ExecStart=/usr/bin/tmux new -d -s worldserver /home/acore/azeroth-server/bin/worldserver
ExecStop=/usr/bin/killall --wait /home/acore/azeroth-server/bin/worldserver
User=acore
Group=acore
RemainAfterExit=yes
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOSF
tee /etc/systemd/system/authserver.service << EOSF
[Unit]
Description=AzerothCore authserver
After=network.target nss-lookup.target time-sync.target remote-fs.target mysqld.service
Requires=mysqld.service

[Service]
Type=simple
WorkingDirectory=/home/acore
ExecStart=/home/acore/azeroth-server/bin/authserver
Restart=on-failure
RestartSec=5
User=acore
Group=acore

[Install]
WantedBy=multi-user.target
EOSF
systemctl daemon-reload
cd ${AZCORE_TEMP}
## Find and download wow data files from github
CLIENT_DATA_VERSION=`curl -s --retry 10 https://github.com/wowgaming/client-data/tags | /usr/local/bin/scrape -e '//a[contains(@class, "Link--primary Link")]/text()' | head -n 1`
curl -LO --retry 10 https://github.com/wowgaming/client-data/releases/download/${CLIENT_DATA_VERSION}/data.zip
unzip data.zip -d /home/acore
cd /tmp
rm -rf ${AZCORE_TEMP}
chown -R acore:acore /home/acore
## Add rebuild acore automation
## Add database backup automation + can you exclude world and it's re-created if other tables populated?
### You can just backup acore_auth and acore_characters
## SELinux
semanage fcontext -a -t bin_t '/home/acore/azeroth-server/bin/.*'
chcon -Rv -u system_u -t bin_t '/home/acore/azeroth-server/bin/'
restorecon -R -v /home/acore/azeroth-server/bin
semanage fcontext -a -t bin_t '/usr/bin/tmux'
chcon -Rv -u system_u -t bin_t '/usr/bin/tmux'
restorecon -R -v /usr/bin/tmux
systemctl enable authserver
systemctl start authserver
sleep 10
## If new -- use acore_auth;
##   Get IP from network load balancer
### OCI_CID=`oci-compartmentid`
OCI_NLB_IP=`oci nlb network-load-balancer list --compartment-id ${OCI_CID} --all | jq --arg realm "${AZCORE_REALM}" -Mr '.data.items[] | select(."defined-tags".acore.realm==$realm)."ip-addresses"[] | select(."is-public" == true)."ip-address"'`
##   UPDATE realmlist SET address = '[your_ip]' WHERE id = 1;
echo "use acore_auth; UPDATE realmlist SET address = \"${OCI_NLB_IP}\", name = \"${AZCORE_REALM}\" WHERE id = 1;" | mysql --password="${ROOT_MYSQL}"
systemctl enable worldserver
systemctl start worldserver
sleep 120
