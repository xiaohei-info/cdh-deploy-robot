#/bin/bash

# ds安装路径
ds_install_path=/tmp/ds_install

db_host=cdh2-3

mysql_passwd=

# zk地址列表
zk_hosts=cdh2-1:2181,cdh2-2:2181,cdh2-3:2181

# 所有可用节点列表
ips=cdh2-1,cdh2-2,cdh2-3

# master节点列表
masters=cdh2-1

# work节点列表
workers=cdh2-2,cdh2-3

# 警报服务器节点
alertServer=cdh2-1

# 后端api服务器节点
apiServers=cdh2-1

# yarn ha 节点列表，没有ha则填空字符串
yarnHaIps=""

# yarn单节点
singleYarnIp=cdh2-1

function say {
    printf '\033[1;4;%sm %s: %s \033[0m\n' "$1" "$2" "$3"
}

function err {
    say "31" "!!!![error]!!!! deploy failed" "$1" >&2
    exit 1
}

function info {
    say "32" "####[info]#### process info" "$1" >&1
}


ds_backend_install_path=$ds_install_path/escheduler-backend
ds_ui_install_path=$ds_install_path/escheduler-ui

info "ds_backend_install_path: $ds_backend_install_path"
info "ds_ui_install_path: $ds_ui_install_path"

mkdir -p $ds_install_path
mkdir $ds_backend_install_path $ds_ui_install_path
mv /tmp/escheduler-*-backend.tar.gz $ds_install_path/escheduler-backend
mv /tmp/escheduler-*-ui.tar.gz $ds_install_path/escheduler-ui

info "get gz file, start unzip..."

cd $ds_install_path/escheduler-backend && tar -zxvf *.tar.gz && rm -rf *.tar.gz
cd $ds_install_path/escheduler-ui && tar -zxvf *.tar.gz && rm -rf *.tar.gz

info "unzip done."

info "create database on $db_host."

ssh $db_host <<EOF
mysql -u root -p"$mysql_passwd" -e "CREATE DATABASE escheduler DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;"
mysql -u root -p"$mysql_passwd" -e "GRANT ALL PRIVILEGES ON escheduler.* TO 'escheduler'@'%' IDENTIFIED BY 'escheduler@DW';"
mysql -u root -p"$mysql_passwd" -e "GRANT ALL PRIVILEGES ON escheduler.* TO 'escheduler'@'localhost' IDENTIFIED BY 'escheduler@DW';"
mysql -u root -p"$mysql_passwd" -e "flush privileges;"
EOF

sed -i "s/192.168.xx.xx/$db_host/" $ds_backend_install_path/conf/dao/data_source.properties
sed -i "s/username=root/username=escheduler/" $ds_backend_install_path/conf/dao/data_source.properties
sed -i "s/password=root@123/password=escheduler@DW/" $ds_backend_install_path/conf/dao/data_source.properties

info "data_source.properties edited."

sh $ds_backend_install_path/script/create_escheduler.sh

sed -i 's/mysqlHost="192.168.xx.xx:3306"/mysqlHost="'$db_host':3306"/' $ds_backend_install_path/install.sh
sed -i 's/mysqlUserName="xx"/mysqlUserName="escheduler"/' $ds_backend_install_path/install.sh
sed -i 's/mysqlPassword="xx"/mysqlPassword="escheduler@DW"/' $ds_backend_install_path/install.sh
sed -i 's/data1_1T/opt/' $ds_backend_install_path/install.sh
sed -i 's/deployUser="escheduler"/deployUser="root"/' $ds_backend_install_path/install.sh
sed -i "s/192.168.xx.xx:2181,192.168.xx.xx:2181,192.168.xx.xx:2181/$zk_hosts/" $ds_backend_install_path/install.sh
sed -i 's/ips="ark0,ark1,ark2,ark3,ark4"/ips="'$ips'"/' $ds_backend_install_path/install.sh
sed -i 's/masters="ark0,ark1"/masters="'$masters'"/' $ds_backend_install_path/install.sh
sed -i 's/workers="ark2,ark3,ark4"/workers="'$workers'"/' $ds_backend_install_path/install.sh
sed -i 's/alertServer="ark3"/alertServer="'$alertServer'"/' $ds_backend_install_path/install.sh
sed -i 's/apiServers="ark1"/apiServers="'$apiServers'"/' $ds_backend_install_path/install.sh
sed -i 's/mycluster:8020/ns1:8020/' $ds_backend_install_path/install.sh
sed -i 's/yarnHaIps="192.168.xx.xx,192.168.xx.xx"/yarnHaIps="'$yarnHaIps'"/' $ds_backend_install_path/install.sh
sed -i 's/singleYarnIp="ark1"/singleYarnIp="'$singleYarnIp'"/' $ds_backend_install_path/install.sh

info "install.sh edited."

cp /opt/cloudera/parcels/CDH/etc/hadoop/conf.dist/core-site.xml $ds_backend_install_path/conf
cp /opt/cloudera/parcels/CDH/etc/hadoop/conf.dist/hdfs-site.xml $ds_backend_install_path/conf

info "cp hadoop config file to $ds_backend_install_path/conf"

sed -i 's/-Xmx16g -Xms4g/-Xmx4g -Xms2g/' $ds_backend_install_path/bin/escheduler-daemon.sh

info "change daemon jvm setting to -Xmx4g -Xms2g"

pip3.6 install kazoo
pip3 install kazoo
pip2.7 install kazoo

java_cmd=`which java`
ln -s $java_cmd /bin/java

info "link $java_cmd to /bin/java"

chmod -R 777 $ds_ui_install_path/dist

info "install backend"

cd $ds_backend_install_path && sh $ds_backend_install_path/install.sh

info "install ui"

cd $ds_ui_install_path && sh $ds_ui_install_path/install-escheduler-ui.sh

