# CDH集群自动化部署工具

CDH集群安装与部署的自动化脚本工具，简单支持「**一键装机**」。

集群部署规划与说明参考：[CDH集群部署最佳实践](http://www.baidu.com)。

## 一、Features

已实现的自动化功能（仅支持Redhat/CentOS系列）：

1. ssh免密登录，执行参数: init_ssh
2. 统一软件安装，执行参数: install_softs
3. 操作系统优化，执行参数: init_sys
4. Java、Scala、Python等开发环境安装配置，执行参数: init_dev
5. MySQL安装、配置与初始化，执行参数: init_mysql
6. CM组件安装、配置与初始化，执行参数: init_cm
7. 操作系统性能测试，执行参数: test_sys
8. CDH组件（HDFS/HBase/Yarn等）配置建议，执行参数: init_config

## 二、Getting Start

在主机中选择一台执行操作过程，以下称为「**控制主机**」，并确保主机外网可用。

### 2.1 安装包准备

当前仅支持离线安装，需要提前下载所需软件安装包，如下：

- JDK
    - 下载地址：[Cloudera Archive CM](https://archive.cloudera.com/cm6/)
    - 说明：版本无限制，仅支持 Oracle JDK RPM包，名称格式为 **oracle-j2sdk\*.rpm**
    - 示例安装包：oracle-j2sdk1.8-1.8.0+update141-1.x86_64.rpm
- Scala
    - 下载地址：[Scala](https://www.scala-lang.org/download/all.html)
    - 说明：版本无限制，仅支持tgz包，名称格式为 **scala\*.tgz**
    - 示例安装包：scala-2.11.8.tgz
- MySQL
    - 下载地址：[MySQL](https://dev.mysql.com/downloads/mysql/5.7.html#downloads)
    - 说明：5.7以上版本，仅支持RPM Bundle包，名称格式为 **mysql\*-bundle.tar**
    - 示例安装包：mysql-5.7.20-1.el7.x86_64.rpm-bundle.tar
- MySQL驱动包（5.1.46）
    - 下载地址：[MySQL Connector](https://dev.mysql.com/downloads/connector/j/5.1.html)
    - 说明：与MySQL版本对应，名称格式为 **mysql-connector-java-\*.tar.gz**
    - 示例安装包：mysql-connector-java-5.1.46.tar.gz
- Cloudera Manager
    - 下载地址：[Cloudera Archive CM](https://archive.cloudera.com/cm6/)
    - 说明：版本无限制
    - 示例安装包：
        - cloudera-manager-server-db-2-6.1.0-853290.el7.x86_64.rpm
        - cloudera-manager-server-6.1.0-853290.el7.x86_64.rpm
        - cloudera-manager-daemons-6.1.0-853290.el7.x86_64.rpm
        - cloudera-manager-agent-6.1.0-853290.el7.x86_64.rpm
- CDH
    - 下载地址：[Cloudera Archive CDH](https://archive.cloudera.com/cdh6/)
    - 说明：版本无限制
    - 示例安装包：
        - manifest.json
        - CDH-6.1.0-1.cdh6.1.0.p0.770702-el7.parcel

百度云打包下载所有示例安装包：

```shell
链接:https://pan.baidu.com/s/1zc5rpTSbutAuzVlyybjVkw  
密码:txa9
```

**上传所有安装包至控制主机的/tmp路径下。**

### 2.2 获取脚本

```shell
yum install -y git
git clone https://github.com/chubbyjiang/cdh-deploy-robot.git
cd cdh-deploy-robot
```

### 2.3 修改hosts文件

```shell
vi hosts
```

将集群所有节点的ip与hostname写入hosts文件中，格式同/etc/hosts，ip与hosts之间空格隔开。

### 2.4 修改配置文件

```shell
vi deploy-robot.cnf
```

- control_host: 控制主机节点hostname
- host_user: 集群主机用户名，需要有root权限
- host_passwd: 集群主机用户密码，所有主机需要一致
- contrast_host: 网络测试使用的节点hostname
- mysql_host: MySQL安装的节点hostname
- mysql_data_dir: MySQL数据路径，最好使用挂载的硬盘
- mysql_binlog_dir: MySQL binlog数据路径，最好使用挂载的硬盘
- mysql_root_passwd: MySQL 初始化之后将使用此密码作为 root 用户密码
- cm_host: cm server节点hostname
- cm_install_path: cdh parcel包路径
- cm_db_passwd: cm数据库初始化密码

### 2.5 执行脚本

```shell
sh deploy-robot.sh install_all
```

That's All!

## 三、使用说明

### 3.1 脚本参数

```shell
sh deploy-robot.sh 
Usage: <type>
```

执行脚本需要指定「**执行类型**」参数。

除了Features中各个功能的执行参数之外，**install_all** 将会依次执行1-7步骤。

### 3.2 CDH组件配置建议

「**配置建议脚本**」 将会读取节点基本配置与相关设置规则信息（cdh_config.cnf），由此计算并输出CDH各个组件的 **重要配置项** 推荐内容。

安装脚本中 install_all 选项将不会执行此步骤，需要单独执行 init_config 选项（调用「配置建议脚本」参数为all）。

或者手动调用「配置建议脚本」。

#### 3.2.1 执行配置建议脚本

```
sh cdh_config.sh
Usage: <type>
```

执行脚本需要指定 「**组件类型**」 参数。

当前组件支持范围：

- hbase
- hdfs
- yarn
- spark
- kafka
- all

#### 3.2.2 输出的重要配置项

**hbase**

- RegionServer JavaHeap Size
- hbase.hregion.max.filesize
- hbase.hregion.memstore.flush.size
- hbase.hregion.memstore.block.multiplier
- hbase.regionserver.global.memstore.upperLimit
- hbase.regionserver.global.memstore.lowerLimit
- hfile.block.cache.size
- hbase.bucketcache.size
- hbase.bucketcache.ioengine
- hbase.bucketcache.percentage.in.combinedcache
- hbase.master.handler.count
- hbase.regionserver.handler.count
- hbase.client.retries.number
- hbase.rpc.timeout
- hbase.hstore.blockingStoreFiles
- hbase.regionserver.regionSplitLimit
- HBase RegionServer Java Configuration

对于 **大规模数据+高并发+毫秒级响应的OLTP实时系统** 场景来说，HBase的部署架构、配置优化、内存规划和使用技巧极其重要，决定了HBase能够承载的请求和性能。

「配置建议脚本」从节点总体磁盘、可用内存、javaheap、region、memstore、堆内堆外内存 等各个维度根据所给的机器配置项计算最佳内存模式与相应配置参数。

有关HBase的性能、配置优化与配置项计算说明可以参考：[HBase最佳实践](www.baidu.com)。 

**hdfs**

- 启用HA
- hadoop.http.staticuser.user
- dfs.replication
- io.compression.codec
- dfs.datanode.handler.count
- dfs.datanode.max.transfer.threads
- dfs.namenode.handler.count
- dfs.namenode.service.handler.count

**yarn**

- Service Monitor Client Configuration
- Yarn Service Mapreduce Advanced Configuration Code Snippet
- mapreduce.output.fileoutputformat.compress
- mapreduce.output.fileoutputformat.compress.type
- mapreduce.output.fileoutputformat.compress.codec
- mapreduce.map.output.compress.codec
- mapreduce.map.output.compress
- zlib.compress.level
- yarn.nodemanager.resource.memory-mb
- yarn.app.mapreduce.am.resource.cpu-vcores
- yarn.scheduler.minimum-allocation-mb
- yarn.scheduler.maximum-allocation-mb
- yarn.scheduler.minimum-allocation-vcores
- yarn.scheduler.maximum-allocation-vcores

**spark**

- spark.hadoop.mapred.output.compress
- spark.hadoop.mapred.output.compression.codec
- spark.hadoop.mapred.output.compression.type
- PYSPARK_PYTHON

**kafka**

- num.partitions

其他配置内容主要为生产环境中验证过的经验值，可视集群情况修改。

输出的配置内容为组件部署完毕后需要调整的配置项，提供参考。

#### 3.2.3 cdh_config.cnf 配置文件说明

```shell
# 节点配置
# 节点可用磁盘空间，单位G
machine_disk=10240
# 节点可用内存大小，单位G
machine_memory=72
# 节点可用cpu核心数
machine_cores=8
# 磁盘使用安全阈值，默认85%的磁盘总空间
machine_disk_ava_threds=0.85
# 内存使用安全阈值，默认85%的内存总空间
machine_memory_ava_threds=0.85
# 以上配置可通过在执行「安装脚本」之后获得

# hdfs
# hdfs副本数
hdfs_replication=3
# 是否开启压缩
enable_compression=true

# hbase
# 安全磁盘空间使用范围内，hbase可用的磁盘空间比例，默认全部
hbase_disk_ava_threds=0.9
# 安全内存空间使用范围内，hbase可用的内存空间比例，默认80%（预留一部分给HDFS等其他服务）
hbase_memory_ava_threds=0.8
# region最小大小，单位G
region_min_size=10
# region最大大小，单位G
region_max_size=30
# 设置单机点最佳的region个数
best_region_num=200
# memstore刷写大小
memstore_flush_size=256

# bucketcache模式参数
# hbase可用内存中，javaheap堆内内存最大可用阈值
javaheap_ava_threds=0.35
# javaheap可用内存中，安全使用阈值
javaheap_safaty_threds=0.79
# java_heap最大大小
javaheap_max_size=56
# java_heap最小大小
javaheap_min_size=4
# upperlimit与lowerlimit差距值
upper2lower_threds=0.1
# region大小调整时，一次调整的步伐，单位G
region_size_incr_step=5
# lowerlimit最大大小
max_lower_limit=0.7
# lowerlimit最小大小
min_lower_limit=0.4

# lru模式参数
# hbase可用安全内存范围中，memstore（即写缓存）占比
lru_memstore_threds=0.45
# hbase可用安全内存范围中，lru读缓存占比大小
lru_blockcache_threds=0.3

# yarn
# 节点可用cores中，yarn可使用的cores占比
yarn_core_ava_threds=0.8
# 节点可用内存中，yarn可使用的内存占比
yarn_memory_ava_threds=0.8
# yarn 单个container 最小分配内存，单位G
yarn_container_min_memory=1
# yarn 单个container 最大分配内存，单位G
yarn_container_max_memory=10
# yarn 单个container 最小分配core
yarn_container_min_cores=1
# yarn 单个container 最大分配core
yarn_container_max_cores=10

# kafka
# topic默认分区数
num_partitions=8
```

以上配置项中，除了节点的磁盘、内存、cpu大小需要指定，其余可使用默认值执行。

### 3.3 yum软件安装列表

yum_requirements.txt 文件中描述了需要在集群各个节点上安装的软件名。

**脚本执行过程中依赖相关软件，默认的软件列表不建议修改**。

### 3.4 python package安装列表

py_requirements.txt 文件中描述了需要在集群各个节点上安装的python包名。

当前安装脚本中并未使用，可通过以下命令自行安装：

```shell
pip3.6 install -r py_requirements.txt
```

## 四、其他

### 4.1 注意事项

1. 使用安装脚本时，如果已生成过ssh密钥，那么ssh的key与认证信息将被**重置**。如果之前配置过ssh信息请注意更新ssh key。或者选择不要执行init_ssh，手动进行ssh配置。
2. 建议在即将投入生产或者干净的主机上运行，以免破坏已有生产系统环境。
3. CM安装过程中**不会启用SSL**

### 4.2 TODO LIST

- 自动化获取节点硬件配置信息以供「配置建议脚本」使用
- LDAP配置支持
- Kerberos配置支持
- CDH集群性能测试

尽管脚本已经经过测试与验证，但是受限于可用的硬件资源与测试环境比较单一，在各种不同的环境中仍然可能出现异常现象。使用过程中任何问题、意见、问题与改进建议，欢迎提交issue讨论与优化。