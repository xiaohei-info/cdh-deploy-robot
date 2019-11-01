#/bin/bash

# ds安装路径
ds_install_path=/root/escheduler

# zk地址列表
zk_hosts="bigdata-1.baofoo.cn:2181,bigdata-2.baofoo.cn:2181,bigdata-3.baofoo.cn:2181"

# 所有可用节点列表
ips="bigdata-1.baofoo.cn,bigdata-2.baofoo.cn,bigdata-3.baofoo.cn"

# master节点列表
masters="bigdata-1.baofoo.cn"

# work节点列表
workers="bigdata-2.baofoo.cn,bigdata-3.baofoo.cn"

# 警报服务器节点
alertServer="bigdata-1.baofoo.cn"

# 后端api服务器节点
apiServers="bigdata-1.baofoo.cn"

# yarn ha 节点列表，没有ha则填空字符串
yarnHaIps=""

# yarn单节点
singleYarnIp="bigdata-1.baofoo.cn"

ds_backend_install_path=$ds_install_path/escheduler-backend
ds_ui_install_path=$ds_install_path/escheduler-ui

mkdir -p $ds_install_path
mkdir $ds_backend_install_path $ds_ui_install_path
mv /tmp/escheduler-*-backend.tar.gz $ds_install_path/escheduler-backend
mv /tmp/escheduler-*-ui.tar.gz $ds_install_path/escheduler-ui
cd $ds_install_path/escheduler-backend && tar -zxvf *.tar.gz && rm -rf *.tar.gz
cd $ds_install_path/escheduler-ui && tar -zxvf *.tar.gz && rm -rf *.tar.gz

ssh $db_host <<EOF
mysql -u root -p"$mysql_passwd" -e "CREATE DATABASE escheduler DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;"
mysql -u root -p"$mysql_passwd" -e "GRANT ALL PRIVILEGES ON escheduler.* TO 'escheduler'@'%' IDENTIFIED BY 'escheduler@DW';"
mysql -u root -p"$mysql_passwd" -e "GRANT ALL PRIVILEGES ON escheduler.* TO 'escheduler'@'localhost' IDENTIFIED BY 'escheduler@DW';"
mysql -u root -p"$mysql_passwd" -e "flush privileges;"
EOF

sed -i "s/192.168.xx.xx/$db_host/" $ds_backend_install_path/conf/dao/data_source.properties
sed -i "s/username=root/username=escheduler/" $ds_backend_install_path/conf/dao/data_source.properties
sed -i "s/password=root@123/password=escheduler@DW/" $ds_backend_install_path/conf/dao/data_source.properties

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

cp /opt/cloudera/parcels/CDH/etc/hadoop/conf.dist/core-site.xml $ds_backend_install_path/conf
cp /opt/cloudera/parcels/CDH/etc/hadoop/conf.dist/hdfs-site.xml $ds_backend_install_path/conf

sed -i 's/-Xmx16g -Xms4g/-Xmx4g -Xms2g/' $ds_backend_install_path/bin/escheduler-daemon.sh

pip3.6 install kazoo
pip3 install kazoo
pip2.7 install kazoo

java_cmd=`which java`
ln -s $java_cmd /bin/java

chmod -R 777 $ds_ui_install_path/dist

sh $ds_backend_install_path/install.sh
sh $ds_ui_install_path/install-escheduler-ui.sh

