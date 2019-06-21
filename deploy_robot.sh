#!/bin/bash
#
if [ $# -lt 1 ]
then
    echo "Usage: [config file]"
    exit 1
fi

# 定义配置项
declare -A CONFIG_NANME=(
    ["EXEC"]="exec_type"
    ["CTRL_HOST"]="control_host"
    ["USER"]="control_user"
    ["PASSWD"]="control_passwd"
    ["CONTRAST"]="contrast_host"
    ["DB_HOST"]="mysql_host"
    ["DB_DATA_DIR"]="mysql_data_dir"
    ["DB_BINLOG_DIR"]="mysql_binlog_dir"
    ["DB_ROOT_PASSWD"]="mysql_root_passwd"
    ["CM_HOST"]="cm_host"
    ["CM_INSTALL_PATH"]="cm_install_path"
    ["CM_DB_PASSWD"]="cm_db_passwd"
    )

declare -A config_map=()

export TOP_PID=$$
trap 'exit 1' TERM

function quit {
    kill -s TERM $TOP_PID
}

function say {
    printf '\033[%sm %s: %s \033[0m\n' "$1" "$2" "$3"
}

function err {
    say "31" "!!!![error]!!!! deploy failed" "$1" >&2
    exit 1
}

function info {
    say "32" "####[info]#### executive info" "$1" >&1
}

function check_cmd {
    command -v "$1" > /dev/null 2>&1
}

function need_cmd {
    if ! check_cmd "$1"; then
        err "need '$1' (command not found)"
    fi
}

function need_ok {
    if [[ $? -ne 0 ]]; then err "$1"; fi
}

# 配置文件检查
function need_config {
    if [ -z $1 ]
    then
        err "need key to get config"
    else
        c=${config_map[$1]}
        if [ -z $c ]
        then
            err "config not found $1"
        fi
    fi
}

# 获取配置文件内容
function get_config {
    need_config $1
    eval $2=${config_map[$1]}
    info "get config $1:${config_map[$1]}"
}

# 文件是否存在
function have {
    if [ ! -f $1 ]
    then
        err "$1 file doesn't exists"
    fi
}

# 初始化配置文件
function init_config {
    info "config loading..."
    config_file=$1
    info "get config_file $config_file"
    have $config_file
    config_arr=`cat $config_file | grep '='`
    for c in ${config_arr}
    do
        arr=(${c//=/ })
        key=${arr[0]}
        value=${arr[1]}
        config_map[$key]=$value
    done
    info "config load finished"
    echo 
}

function get_home {
    if [ $1 == "root" ]
    then
        user_home="/root"
    else
        user_home="/home/$user"
    fi
    info "operate user home : $user_home"
    echo
}


function init_hosts {
    # 解析主机列表
    info "hosts loading..."
    info "get host_file $SELF/hosts"
    host_file=$SELF/hosts
    have $host_file
    declare -A hostip_map=()
    host_arr=`cat $host_file | sed s'/ /,/'`
    for a in ${host_arr[*]}
    do
        if [ -n $a ]
        then
            arr=(${a//,/ })
            ip=${arr[0]}
            host=${arr[1]}
            need_ok "host dosen't formated: $a"
            hostip_map[$host]=$ip
        fi
    done
    #key
    hosts=${!hostip_map[@]} 
    info "hosts: ${hosts[*]}"
    #value
    ips=${hostip_map[@]} 
    info "ips: ${ip[*]}"
    info "hosts load finished"
    echo
}

function set_hosts {
    # 主机名设置
    info "start setting /etc/hosts and config ssh keys"
    yum install -y expect
    need_cmd expect
    info "get expect_file from github"
    wget -P $tmp_path https://raw.githubusercontent.com/chubbyjiang/cdh-deploy-robot/master/expect.sh
    expect_file=$tmp_path/expect.sh
    have $expect_file
    cat /etc/hosts | head -n 2 > /etc/hosts
    cat $host_file >> /etc/hosts
    info "hosts added to /etc/hosts"
    curr_hosts=`cat /etc/hosts`
    info "current hosts: ${curr_hosts[*]}"
    info "start config ssh key(all hosts)"
    for host in ${hosts[*]}
    do
        info "set hostname $host"
        expect $expect_file ssh $host $user $passwd "hostnamectl set-hostname $host"
        info "scp /etc/hosts"
        expect $expect_file scp $host $user $passwd /etc/hosts
        info "gen ssh key"
        expect $expect_file ssh $host $user $passwd "ssh-keygen -t rsa"
        expect $expect_file ssh $host $user $passwd "cat $user_home/.ssh/id_rsa.pub > $user_home/.ssh/authorized_keys"
        info "copy id to ctrl host"
        echo "" > $user_home/.ssh/authorized_keys
        expect $expect_file ssh $host $user $passwd "ssh-copy-id -i $user_home/.ssh/id_rsa.pub $user@$ctrl_host"
    done
    info "all hosts ssh key done"
    info "scp authorized_keys to all hosts"
    for host in ${hosts[*]}
    do
        info "$host"
        expect $expect_file scp $host $user $passwd $user_home/.ssh/authorized_keys
    done
    info "scp authorized_keys done"
    echo
}

function install_ansible {
    # 安装ansible
    info "start install ansible"
    yum install -y ansible
    need_cmd ansible
    echo "[all]" > /etc/ansible/hosts
    echo ${hosts[*]} >> /etc/ansible/hosts
    info "ansible finish config"
    echo
}

function set_selinux {
    # selinux
    selinux_stat=`getenforce | tr 'A-Z' 'a-z'`
    info "setting selinux, current: $selinux_stat"
    if [ $selinux_stat == "enforcing" ]
    then
        info "change to disable"
        sed -i s'/SELINUX=enforcing/SELINUX=disable' /etc/selinux/config
        sed -i s'/SELINUX=Enforcing/SELINUX=disable' /etc/selinux/config
        curr=`cat /etc/selinux/config | grep SELINUX`
        info "current: $curr"
    fi
    info "sync to hosts"
    ansible all -m copy -a "src=/etc/selinux/config dest=/etc/selinux/config"
    info "done"
    echo
}

#ipv6设置
function set_ipv6 {
    ipv6_stat=`lsmod | grep ipv6`
    info "setting ipv6 stat, current: $ipv6_stat"
    if [ -n $ipv6_stat ]
    then
        info "change to disable"
        original=`cat /etc/default/grub | grep GRUB_CMDLINE_LINUX | awk -F '="' '{print $2}'`
        result="GRUB_CMDLINE_LINUX=\"ipv6.disable=1 "$original
        cat /etc/default/grub | grep -v GRUB_CMDLINE_LINUX > /etc/default/grub
        echo $result >> /etc/default/grub
        curr=`cat /etc/default/grub | grep GRUB_CMDLINE_LINUX`
        info "current: $curr"
        info "sync to hosts"
        ansible all -m copy -a "src=/etc/default/grub dest=/etc/default/grub"
    fi   
    info "done"
    echo
}


function set_firewall {
   # 防火墙设置
    info "disable firewalld"
    ansible all -a "iptables-save > /root/firewall.rules"
    ansible all -a "systemctl status firewalld"
    ansible all -a "systemctl stop firewalld"
    ansible all -a "systemctl disable firewalld"
    ansible all -a "chkconfig iptables off"
    ansible all -a "service iptables status"
    ansible all -a "service iptables stop" 
    info "firewalld disabled"
    echo
}


function set_dns {
    # dns服务器
    info "add dns server"
    is_exists=`cat /etc/resolv.conf | grep 114 | wc -l`
    if [ $is_exists -eq 0 ]
    then
        echo "nameserver 114.114.114.114" >> /etc/resolv.conf
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf 
    else
        info "dns has been setup"
    fi
    info "sync to hosts"
    ansible all -m copy -a "src=/etc/resolv.conf dest=/etc/resolv.conf"
    info "dns done"
    echo
}

function set_ntp {
    # ntp配置
    info "start ntp server"
    info "change timezone info to Shanghai"
    ansible all -m shell -a "rm -rf /etc/localtime && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime"
    info "install ntpd"
    ansible all -a "yum install ntp -y"
    info "sync time to 0.cn.pool.ntp.org"
    ansible all -a "ntpdate -u 0.cn.pool.ntp.org"
    info "add ntp1.aliyun.com to ntp.conf"
    is_exists=`cat /etc/ntp.conf | grep aliyun | wc -l`
    if [ $is_exists -eq 0 ]
    then
        echo "server ntp1.aliyun.com" >> /etc/ntp.conf
    fi
    ansible all -a "systemctl start ntpd"
    ansible all -a "systemctl enable ntpd"
    info "ntp done"
    echo
}

function set_yum {
    # 更新yum源
    info "start set yum"
    if [ ! -f /etc/yum.repos.d/CentOS-Base.repo.backup ]
    then
        mv /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.backup
    fi
    ansible all -a "wget -O /etc/yum.repos.d/CentOS-Base.repo http://mirrors.aliyun.com/repo/Centos-7.repo"
    ansible all -m shell -a "yum clean all && yum makecache"
    ansible all -a "yum -y update"
    
    # 安装系统软件
    info "install softs"
    ansible all -a "yum install -y net-tools iotop zip unzip telnet wget iperf fio ntfs-3g lzo iftop"
    info "done"
    echo
}

function set_java {
    # java
    info "start set java"
    java_file=`ls $tmp_path/oracle-j2sdk*.rpm`
    have $java_file
    info "get jdk $java_file"
    ansible all -m copy -a "src=$java_file dest=$java_file"
    ansible all -m shell -a "yum localinstall -y $java_file"
    jdk_path=`ls /usr/java/jdk*`
    info "jdk path: $jdk_path"
    ansible all -m copy -a "rm -rf /usr/java/default && ln -s $jdk_path /usr/java/default"
    info "done"
    echo
}

function set_scala {
    # scala
    info "start set scala"
    scala_file=`ls $tmp_path/scala*.tgz`
    have $scala_file
    info "get scala file $scala_file"
    ansible all -m shell -a "rm -rf /usr/scala && mkdir -p /usr/scala"
    mv $scala_file /usr/scala
    scala_file=`ls /usr/scala/scala*.tgz`
    ansible all -m copy -a "src=$scala_file dest=$scala_file"
    ansible all -m shell -a "tar -zxvf $scala_file && rm -rf $scala_file"
    info "done"
    echo
}

function set_profile {
    # 配置环境变量
    scala_dir_name=`ls /usr/scala/scala*`
    setting="JAVA_HOME=$jdk_path\nSCALA_HOME=$scala_dir_name\nCLASSPATH=\$JAVA_HOME/bin:\$SCALA_HOME/bin\nexport PATH=\$JAVA_HOME:\$SCALA_HOME:\$CLASSPATH:\$PATH\n"
    info "profile setting: $setting"
    is_exists=`cat /etc/profile | grep JAVA_HOME | wc -l`
    if [ $is_exists -eq 0 ]
    then
        echo -e $setting >> /etc/profile
        ansible all -m copy -a "src=/etc/profile dest=/etc/profile"
        ansible all -a "source /etc/profile"
    fi
    info "done"
    echo
}

function set_python {
    info "start set python"
    if [ ! check_cmd python3.6 ]
    then
        # python
        info "install dev packages"
        ansible all -a "yum install -y openssl-devel bzip2-devel expat-devel gdbm-devel readline-devel sqlite-devel gcc-c++ python36-devel cyrus-sasl-lib.x86_64 cyrus-sasl-devel.x86_64 libgsasl-devel.x86_64 epel-release"
        # yum源下载
        ansible all -a "yum install https://centos7.iuscommunity.org/ius-release.rpm -y"
        # 安装python3.6
        info "install python36"
        ansible all -a "yum install python36 -y"
    else
        info "python36 already installed"
    fi
    
    # todo:check是否是easy_install-3.6
    if [ ! check_cmd easy_install-3.6 ]
    then
        # 安装setuptools
        info "install setuptools"
        ansible all -a "wget -P $tmp_path --no-check-certificate https://pypi.python.org/packages/source/s/setuptools/setuptools-19.6.tar.gz#md5=c607dd118eae682c44ed146367a17e26"
        ansible all -a "tar -zxvf $tmp_path/setuptools-19.6.tar.gz"
        ansible all -m shell -a "cd $tmp_path/setuptools-19.6 && python3.6 setup.py build && python3.6 setup.py install"
    else
        info "easy_install-3.6 already installed"
    fi

    if [ ! check_cmd pip3.6 ]
    then
        # 安装pip3.6
        info "install pip"
        ansible all -a "wget -P $tmp_path --no-check-certificate https://pypi.python.org/packages/source/p/pip/pip-8.0.2.tar.gz#md5=3a73c4188f8dbad6a1e6f6d44d117eeb"
        ansible all -a "tar -zxvf $tmp_path/pip-8.0.2.tar.gz"
        ansible all -m shell -a "cd $tmp_path/pip-8.0.2 && python3.6 setup.py build && python3.6 setup.py install"
    else
        info "pip3.6 already installed"
    fi

    # 修改pip源
    info "change pip source"
    ansible all -m shell -a "rm -rf $user_home/.pip && mkdir $user_home/.pip"
    echo -e "[global]\nindex-url = https://pypi.tuna.tsinghua.edu.cn/simple" > $user_home/.pip/pip.conf
    ansibe all -m copy -a "src=$user_home/.pip/pip.conf dest=$user_home/.pip/pip.conf"
    ansible all -m shell -a "pip3.6 install --upgrade setuptools && easy_install-3.6 -U setuptools && pip3.6 install --upgrade pip"
    # python依赖包安装
    info "install requirements"
    python_require_path=$SELF/requirements.txt
    have $python_require_path
    info "get requirements file: $python_require_path"
    ansibe all -m copy -a "src=$python_require_path dest=$python_require_path"
    ansible all -a "pip3.6 install -r $python_require_path"
    info "done"
    echo
}

function set_tuned {
    info "disable tuned"
    # 关闭tuned
    ansible all -a "systemctl start tuned"
    ansible all -a "systemctl status tuned"
    # 显示No current active profile
    ansible all -a "tuned-adm off"
    ansible all -a "tuned-adm list"
    # 关闭tuned服务
    ansible all -a "systemctl stop tuned"
    ansible all -a "systemctl disable tuned"    
    info "done"
    echo
}

function set_hugepage {
    info "disable hugepage"
    # 关闭大页面
    # 输出[always] never意味着THP已启用，always [never]意味着THP未启用
    curr0=`cat /sys/kernel/mm/transparent_hugepage/enabled`
    curr1=`cat /sys/kernel/mm/transparent_hugepage/defrag`
    info "current: $curr0 \n $curr1"
    is_enable=`cat /sys/kernel/mm/transparent_hugepage/enabled | grep [always] | wc -l`
    is_defrag=`cat /sys/kernel/mm/transparent_hugepage/defrag | grep [always] | wc -l`
    if [ $is_enable -eq 1 ]
    then
        # 关闭
        ansible all -m shell -a "echo never > /sys/kernel/mm/transparent_hugepage/enabled"
        ansible all -m shell -a "echo never > /sys/kernel/mm/transparent_hugepage/defrag"
        # 设置开机关闭
        echo "echo never > /sys/kernel/mm/transparent_hugepage/defrag" >> /etc/rc.local
        echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local
        chmod +x /etc/rc.d/rc.local
        ansible all -m copy -a "src=/etc/rc.d/rc.local dest=/etc/rc.d/rc.local"
        # 在GRUB_CMDLINE_LINUX项目后面添加一个参数：transparent_hugepage=never
        original=`cat /etc/default/grub | grep GRUB_CMDLINE_LINUX | awk -F '="' '{print $2}'`
        result="GRUB_CMDLINE_LINUX=\"transparent_hugepage=never "$original
        cat /etc/default/grub | grep -v GRUB_CMDLINE_LINUX > /etc/default/grub
        echo $result >> /etc/default/grub
        curr2=`cat /etc/default/grub | grep GRUB_CMDLINE_LINUX`
        info "current: $curr2"
        ansible all -m copy -a "src=/etc/default/grub dest=/etc/default/grub"
        # 重新生成gurb.cfg文件
        ansible all -a "grub2-mkconfig -o /boot/grub2/grub.cfg"
    fi
    info "done"
    echo
}

function set_swappiness {
    # swappiness
    info "set swappiness"
    swap_stat=`cat /proc/sys/vm/swappiness`
    info "current: $swap_stat"
    if [ ! $swap_stat -eq 1 ]
    then
        ansible all -a "sysctl -w vm.swappiness=1"
        echo "vm.swappiness=1" >> /etc/sysctl.conf
        curr=`cart /etc/sysctl.conf | grep swappiness`
        info "current: $curr"
        ansible all -m copy -a "src=/etc/sysctl.conf dest=/etc/sysctl.conf"
    fi
    info "done"
    echo
}

function set_tmout {
   # 会话超时设置
    info "set tmout to 900"
    is_exists=`cat /etc/profile | grep TMOUT=900 | wc -l`
    if [ $is_exists -eq 0 ]
    then
        echo "TMOUT=900" >> /etc/profile
        ansble all -m copy -a "src=/etc/profile dest=/etc/profile"
    else
        info "tmout already installed"
    fi
    info "done"
    echo
}

function set_kernel {
    # 内核优化
    info "setting kernel"
    is_exists=`cat /etc/sysctl.conf | grep pid_max | wc -l`
    if [ $is_exists -eq 0 ]
    then
        echo -e "\nnet.ipv4.tcp_tw_reuse = 1
        \nnet.ipv4.tcp_tw_recycle = 1
        \nnet.ipv4.tcp_keepalive_time = 1200
        \nnet.ipv4.ip_local_port_range = 10000 65000
        \nnet.ipv4.tcp_max_syn_backlog = 8192
        \nnet.ipv4.tcp_max_tw_buckets = 5000
        \nfs.file-max = 655350
        \nnet.ipv4.route.gc_timeout = 100
        \nnet.ipv4.tcp_syn_retries = 1
        \nnet.ipv4.tcp_synack_retries = 1
        \nnet.core.netdev_max_backlog = 16384
        \nnet.ipv4.tcp_max_orphans = 16384
        \nnet.ipv4.tcp_fin_timeout = 2
        \net.core.somaxconn=32768
        \kernel.threads-max=196605
        \kernel.pid_max=196605
        \vm.max_map_count=393210"  >> /etc/sysctl.conf && echo 'yes'
    else
        info "kernel already installed"
    fi
    info "done"
    echo
}

function set_maxfiles {
    # 最大打开文件数
    curr=`ulimit -a`
    info "current max files: $curr,change to 196605"
    is_exists=`cat /etc/security/limits.conf | grep 196605 | wc -l`
    if [ $is_exists -eq 0 ]
    then
        sed -i '$ a\* soft nofile 196605' /etc/security/limits.conf
        sed -i '$ a\* hard nofile 196605' /etc/security/limits.conf
        echo "* soft nproc 196605" >> /etc/security/limits.conf
        echo "* hard nproc 196605" >> /etc/security/limits.conf
    else
        info "ulimit already installed"
    fi
    info "done"
    echo
}

function get_sysinfo {
    # 系统环境
    sys_version=`cat /etc/redhat-release`
    info "operator system version: $sys_version"
    java_version=`java -version`
    info "java version: $java_version"
    scala_version=`scala -version`
    info "scala version: $scala_version"
    total_mem=`free -h | grep Mem | awk '{print $2}'`
    info "total memory: $total_mem"
        # 查看物理CPU个数
    cpu_num=`cat /proc/cpuinfo| grep "physical id"| sort| uniq| wc -l`
    info "number of cpu: $cpu_num"
        # 查看每个物理CPU中core的个数(即核数)
    cpu_cores=`cat /proc/cpuinfo| grep "cpu cores"| uniq`
    info "core number per cpu: $cpu_cores"
        # 查看逻辑CPU的个数
    total_cpu=`cat /proc/cpuinfo| grep "processor"| wc -l`
    info "logic cpu cores: $total_cpu"
    cpu_info=`cat /proc/cpuinfo`
    info "cpu info: $cpu_info"
    umask_info=`umask`
    info "umask: $umask_info"
    # fdisk -l
    # lsblk -d -o name,rota
    # df -TH   
    echo
}

function test_network {
    # 网络测试
    info "start network test"
    info "contrast host is: $contrast_host, start iperf server"
    # todo: test
    ssh $contrast_host "iperf3 -s -p 12345 -i 1" &
    info "start iperf client"
    echo "####network test####" > $test_result_file
    iperf3 -c $contrast_host -p 12345 -i 1 -t 10 -w 100K >> $test_result_file
    info "test done,save result to $test_result_file"
    echo
}

function test_io {
    info "start io test"
    # io测试
    # 随机读
    echo "####io test####" >> $test_result_file
    echo "----random read----" >> $test_result_file
    fio -filename=/dev/sda -direct=1 -iodepth 1 -thread -rw=randread -ioengine=psync -bs=4k -size=60G -numjobs=64 -runtime=10 -group_reporting -name=file -allow_mounted_write=1 >> $test_result_file
    # 顺序读
    echo "----sequence read----" >> $test_result_file
    fio -filename=/dev/sda -direct=1 -iodepth 1 -thread -rw=read -ioengine=psync -bs=4k -size=60G -numjobs=64 -runtime=10 -group_reporting -name=file -allow_mounted_write=1 >> $test_result_file
    # 随机写
    echo "----random write----" >> $test_result_file
    fio -filename=/dev/sda -direct=1 -iodepth 1 -thread -rw=randwrite -ioengine=psync -bs=4k -size=60G -numjobs=64 -runtime=10 -group_reporting -name=file -allow_mounted_write=1 >> $test_result_file
    # 顺序写
    echo "----sequence write----" >> $test_result_file
    fio -filename=/dev/sda -direct=1 -iodepth 1 -thread -rw=write -ioengine=psync -bs=4k -size=60G -numjobs=64 -runtime=10 -group_reporting -name=file -allow_mounted_write=1 >> $test_result_file
    # 混合随机读写
    echo "----mix raddom read/write----" >> $test_result_file
    fio -filename=/dev/sda -direct=1 -iodepth 1 -thread -rw=randrw -rwmixread=30 -ioengine=psync -bs=4k -size=60G -numjobs=64 -runtime=10 -group_reporting -name=file -ioscheduler=noop -allow_mounted_write=1 >> $test_result_file
    info "test done,save result to $test_result_file"
    echo
}

function set_mysql {
    # mysql
    info "start set mysql"
    is_exists=`ssh $db_host "mysql" | grep -bash | wc -l`
    if [ $is_exists -eq 1 ]
    then
        info "mysql host: $db_host"
        common_file=`ls $tmp_path/mysql-community-common-*.rpm`
        libs_file=`ls $tmp_path/mysql-libs-common-*.rpm`
        client_file=`ls $tmp_path/mysql-client-common-*.rpm`
        server_file=`ls $tmp_path/mysql-server-common-*.rpm`
        driver_file=`ls $tmp_path/mysql-connector-java-*.tar.gz`
        # 默认为临时路径下
        have $common_file
        have $libs_file
        have $client_file
        have $server_file
        have $driver_file
        info "get mysql install file: $common_file\n$libs_file\n$client_file\n$server_file\n$driver_file"
        
        info "mkdir and scp to mysql host"
        ssh $mysql_host "mkdir -p $tmp_path"
        scp $tmp_path/mysql-community-common-$db_version.rpm $mysql_host:$tmp_path/mysql-community-common-$db_version.rpm
        scp $tmp_path/mysql-community-libs-$db_version.rpm $mysql_host:$tmp_path/mysql-community-libs-$db_version.rpm
        scp $tmp_path/mysql-community-client-$db_version.rpm $mysql_host:$tmp_path/mysql-community-client-$db_version.rpm
        scp $tmp_path/mysql-community-server-$db_version.rpm $mysql_host:$tmp_path/mysql-community-server-$db_version.rpm
        info "scp done"
    
        info "install mysql"
        ssh $db_host <<EOF
        rpm -qa|grep -i mariadb
        rpm -e mariadb-libs-5.5.60-1.el7_5.x86_64 --nodeps
        rpm -ivh $common_file
        rpm -ivh $libs_file
        rpm -ivh $client_file
        rpm -ivh $server_file
        
        mkdir -p $db_data_dir
EOF
    else 
        info "mysql already installed"
    fi

    info "create mysql config"
    ssh $db_host "systemctl stop mysql"
    echo -e "
    [mysqld]\n \
    datadir=$db_data_dir\n \
    socket=/var/lib/mysql/mysql.sock\n \
    transaction-isolation = READ-COMMITTED\n \
    symbolic-links = 0\n \
    key_buffer_size = 32M\n \
    max_allowed_packet = 32M\n \
    thread_stack = 256K\n \
    thread_cache_size = 64\n \
    query_cache_limit = 8M\n \
    query_cache_size = 64M\n \
    query_cache_type = 1\n \
    max_connections = 550\n \
    #expire_logs_days = 10\n \
    #max_binlog_size = 100M\n \
    log_bin=$db_binlog_dir\n \
    server_id=1\n \
    binlog_format = mixed\n \
    read_buffer_size = 2M\n \
    read_rnd_buffer_size = 16M\n \
    sort_buffer_size = 8M\n \
    join_buffer_size = 8M\n \
    innodb_file_per_table = 1\n \
    innodb_flush_log_at_trx_commit  = 2\n \
    innodb_log_buffer_size = 64M\n \
    innodb_buffer_pool_size = 4G\n \
    innodb_thread_concurrency = 8\n \
    innodb_flush_method = O_DIRECT\n \
    innodb_log_file_size = 512M\n \
    [mysqld_safe]\n \
    log-error=/var/log/mysqld.log\n \
    pid-file=/var/run/mysqld/mysqld.pid\n \
    sql_mode=STRICT_ALL_TABLES\n \
    " > /etc/my.conf
    info "get config mysql data dir: $db_data_dir"
    info "get config mysql binlog dir: $db_binlog_dir"
    info "scp config file"
    scp /etc/my.conf $db_host:/etc/my.conf
    info "install mysql driver"
    # 安装mysql驱动
    rm -rf $tmp_path/mysql-connector-java-*/*.jar
    tar zxvf $driver_file
    driver_jar=`ls $tmp_path/mysql-connector-java-*/*.jar`
    info "get driver jar: $driver_jar,scp to hosts"
    ansible all -m copy -a "src=$driver_jar dest=$driver_jar"
    ansible all -a "rm -rf /usr/share/java/ && mkdir -p /usr/share/java/ && mv $driver_jar /usr/share/java/"

    info "scp expect_file to mysql host"
    # expect脚本复制
    scp $expect_file $db_host:$expect_file
    info "get config mysql password: $mysql_passwd"
    info "start mysql server and init db settings"
    # 启动mysql
    ssh $db_host <<EOF
    systemctl start mysqld
    systemctl status mysqld
    systemctl enable mysqld
    # todo: 判断是否可以二次执行
    $expect_file mysql_init $db_host root $mysql_passwd mysql_init
    # todo: 测试是否可以执行
    mysql -u root -p$mysql_passwd <<INNER
    drop database scm;
    drop database amon;
    drop database rman;
    drop database hue;
    drop database metastore;
    drop database sentry;
    drop database nav;
    drop database navms;
    drop database oozie;
    CREATE DATABASE scm DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
    GRANT ALL ON scm.* TO 'scm'@'%' IDENTIFIED BY 'scm@DW';
    CREATE DATABASE amon DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
    GRANT ALL ON amon.* TO 'amon'@'%' IDENTIFIED BY 'amon@DW';
    CREATE DATABASE rman DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
    GRANT ALL ON rman.* TO 'rman'@'%' IDENTIFIED BY 'rman@DW';
    CREATE DATABASE hue DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
    GRANT ALL ON hue.* TO 'hue'@'%' IDENTIFIED BY 'hue@DW';
    CREATE DATABASE metastore DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
    GRANT ALL ON metastore.* TO 'hive'@'%' IDENTIFIED BY 'hive@DW';
    CREATE DATABASE sentry DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
    GRANT ALL ON sentry.* TO 'sentry'@'%' IDENTIFIED BY 'sentry@DW';
    CREATE DATABASE nav DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
    GRANT ALL ON nav.* TO 'nav'@'%' IDENTIFIED BY 'nav@DW';
    CREATE DATABASE navms DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
    GRANT ALL ON navms.* TO 'navms'@'%' IDENTIFIED BY 'navms@DW';
    CREATE DATABASE oozie DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;
    GRANT ALL ON oozie.* TO 'oozie'@'%' IDENTIFIED BY 'oozie@DW';
    SHOW DATABASES;
    INNER
EOF
    info "done"
    echo
}

function set_cm {
    # 安装cm软件包
    info "start set cloudera manager"
    info "get config cm install path: $cm_install_path"
    info "create sudoer and scp to hosts"
    is_exists=`cat /etc/sudoers | grep cloudera-scm | wc -l`
    if [ $is_exists -eq 0 ]
    then
        echo "cloudera-scm    ALL=(ALL)    NOPASSWD:ALL" >> /etc/sudoers
    fi
    ansible all -m copy -a "src=/etc/sudoers dest=/etc/sudoers"
    daemons_file=`ls $tmp_path/cloudera-manager-daemons-*.rpm`
    agent_file=`ls $tmp_path/cloudera-manager-agent-*.rpm`
    have $daemons_file
    have $agent_file
    info "get daemons file:$daemons_file"
    info "get agent file:$agent_file"
    info "scp and install daemons/agent to hosts"
    ansible all -m copy -a "src=$daemons_file dest=$daemons_file"
    ansible all -m copy -a "src=$agent_file dest=$agent_file"
    ansible all -a "rpm -ivh --force --nodeps $daemons_file"
    ansible all -a "rpm -ivh --force --nodeps $agent_file"
    info "daemons/agent installed"
    # 主机节点安装所有包
    info "install packages in ctrl host: $ctrl_host"
    rpm -ivh --force --nodeps $tmp_path/cloudera-manager-server-*.rpm
    # 修改配置文件
    info "get config cm host: $cm_host"
    cat /etc/cloudera-scm-agent/config.ini | grep -v server_host > /etc/cloudera-scm-agent/config.ini
    echo "server_host=$cm_host" >> /etc/cloudera-scm-agent/config.ini
    info "set cm host to config file"
    # cdh
    info "mv cdh parcels to cm install path"
    rm -rf $cm_install_path && mkdir -p $cm_install_path
    mv $tmp_path/CDH-*.parcel $cm_install_path
    mv $tmp_path/manifest.json $cm_install_path
    # cm数据库配置
    info "database config"
    echo -e "com.cloudera.cmf.db.type=mysql\ncom.cloudera.cmf.db.host=$db_host\ncom.cloudera.cmf.db.name=scm\ncom.cloudera.cmf.db.user=scm\ncom.cloudera.cmf.db.setupType=EXTERNAL\ncom.cloudera.cmf.db.password=$cm_db_passwd\n" > /etc/cloudera-scm-server/db.properties
    cat /etc/cloudera-scm-server/db.properties
    info "init db"
    # 初始化数据库
    # todo: test 是否需要 expect
    /opt/cloudera/cm/schema/scm_prepare_database.sh -h $db_host mysql scm scm
    info "start cm server"
    # 启动server
    systemctl start cloudera-scm-server
    # 查看日志
    # tail -f /var/log/cloudera-scm-server/cloudera-scm-server.log
    info "start all cm agent"
    # 各个节点上启动agent
    ansible all -a "systemctl start cloudera-scm-agent"
    info "done"
    echo
}

function init_ssh {
    init_hosts
    set_hosts
}

function install_softs {
    install_ansible
    set_yum
}

function init_system {
    set_selinux
    set_ipv6
    set_firewall
    set_dns
    set_tuned
    set_hugepage
    set_swappiness
    set_tmout
    set_kernel
    set_maxfiles
}

function init_devenv {
    set_java
    set_scala
    set_profile
    set_python
}

function init_mysql {
    set_mysql
}

function test_system {
    test_network
    test_io
    get_sysinfo
    # 内存性能测试
    # 操作系统性能测试
}

function init_cm {
    set_cm
}

SELF=$(cd $(dirname $0) && pwd)
cd $SELF
tmp_path=/tmp
test_result_file=$tmp_path/test_result.txt

info "start deploy process"
init_config $1
# 控制主机与用户名、密码
get_config ${CONFIG_NANME[EXEC]} exec
get_config ${CONFIG_NANME[CTRL_HOST]} ctrl_host
get_config ${CONFIG_NANME[USER]} user
get_config ${CONFIG_NANME[PASSWD]} passwd
get_config ${CONFIG_NANME[CONTRAST]} contrast_host
get_config ${CONFIG_NANME[DB_HOST]} db_host
get_config ${CONFIG_NANME[DB_DATA_DIR]} db_data_dir
get_config ${CONFIG_NANME[DB_BINLOG_DIR]} db_binlog_dir
get_config ${CONFIG_NANME[DB_ROOT_PASSWD]} mysql_passwd
get_config ${CONFIG_NANME[CM_HOST]} cm_host
get_config ${CONFIG_NANME[CM_INSTALL_PATH]} cm_install_path
get_config ${CONFIG_NANME[CM_DB_PASSWD]} cm_db_passwd
get_home $user
if [ "$exec" == "init_ssh" ]
then
    init_ssh
elif [ "$exec" == "install_softs" ]
then
    install_softs
elif [ "$exec" == "init_sys" ]
then
    init_system
elif [[ "$exec" == "init_dev" ]]
then
    init_devenv
elif [[ "$exec" == "init_mysql" ]]
then    
    init_mysql
elif [[ "$exec" == "test_sys" ]]
then 
    test_system
elif [[ "$exec" == "init_cm" ]]
then
    init_cm
elif [[ "$exec" == "all" ]]
then
    init_ssh
    install_softs
    init_system
    init_devenv
    init_mysql
    test_system
    init_cm
else
    info "nothing todo, exit..."
    exit 0
fi
info "all done!!!"
