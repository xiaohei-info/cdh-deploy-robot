#!/bin/bash

if [ $# -lt 2 ]
then
    # hdfs/hbase/yarn/spark/kafka/hue/all
    echo "Usage: <result file path> <type>"
    exit 1
fi

config_result_file=$1
type=$2
echo "Configuration\n" > $config_result_file
declare -A config_map=()

function say {
    printf '\033[1;4;%sm %s: %s \033[0m\n' "$1" "$2" "$3"
}

function err {
    say "31" "!!!![error]!!!! config failed" "$1" >&2
    exit 1
}

function info {
    say "32" "####[info]#### config info" "$1" >&1
}

function calc {
    eval $2=$(echo "scale=4;$1" | bc)
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
    eval $1=${config_map[$1]}
    info "get config $1:${config_map[$1]}."
}

# 文件是否存在
function have {
    if [ ! -f $1 ]
    then
        err "$1 file doesn't exists"
    fi
}

function save {
    echo -e "$1\n" >> $config_result_file
}

# 初始化配置文件
function init_config {
    info "config loading..."
    config_file=$1
    info "get config_file $config_file."
    have $config_file
    config_arr=`cat $config_file | grep '='`
    for c in ${config_arr}
    do
        arr=(${c//=/ })
        key=${arr[0]}
        value=${arr[1]}
        config_map[$key]=$value
    done
    info "config load finished."
    echo 
}

function hdfs_config {
    info "Getting HDFS Configuration..."
    info
    save "####HDFS Configuration####"
    # dfs.replication=$hdfs_replication
    get_config hdfs_replication

    hdfs_config_result="
    Cluster Operator Enable HighAvailability: true\n\
    core-site.xml Advanced Configuration Code Snippet: hadoop.http.staticuser.user=yarn\n\
    dfs.replication=$hdfs_replication\n\
    io.compression.codec=sorg.apache.hadoop.io.compress.DefaultCodec,org.apache.hadoop.io.compress.GzipCodec,org.apache.hadoop.io.compress.BZip2Codec,org.apache.hadoop.io.compress.DeflateCodec,org.apache.hadoop.io.compress.SnappyCodec,org.apache.hadoop.io.compress.Lz4Codec\n\
    dfs.datanode.handler.count=64\n\
    dfs.datanode.max.transfer.threads=12288\n\
    dfs.namenode.handler.count=256\n\
    dfs.namenode.service.handler.count=256\n\
    "
    save "$hdfs_config_result"
    info "hdfs config_result:$hdfs_config_result"
}

# 128G的内存至少要配14T硬盘
# 128G至少需要12T硬盘
function hbase_config {
    info "Getting HBase Configuration..."
    info
    save "####HBase Configuration####"

    get_config hdfs_replication
    get_config hdfs_replication
    calc "$machine_disk * $machine_disk_ava_threds" machine_disk_ava_size
    get_config hbase_disk_ava_threds
    calc "$machine_disk_ava_size * $hbase_disk_ava_threds" hbase_disk_ava_size
    info "hdfs_replication: $hdfs_replication"
    info "machine_disk: $machine_disk G"
    info "machine_disk_ava_threds: $machine_disk_ava_threds"
    info "machine_disk_ava_size: $machine_disk_ava_size G"
    info "hbase_disk_ava_threds: $hbase_disk_ava_threds"
    info "hbase_disk_ava_size: $hbase_disk_ava_size G"

    get_config region_min_size
    get_config region_max_size
    get_config best_region_num
    get_config region_size_incr_step
    best_region_size=$region_min_size
    info "region_min_size: $region_min_size G"
    info "region_max_size: $region_max_size G"
    info "best_region_num: $best_region_num"
    info "region_size_incr_step: $region_size_incr_step G"
    info "init best_region_size: $best_region_size G"
    info
    while test $best_region_size -le $region_max_size
    do
        calc "$hbase_disk_ava_size / ($best_region_size * $hdfs_replication)" curr_region_size
        info "curr_region_size: $curr_region_size"
        calc "$curr_region_size > 200" gt_best
        calc "$curr_region_size < 20" lt_best
        if test $gt_best -eq 1
        then
            calc "$best_region_size + $region_size_incr_step" best_region_size
            info "best_region_size = best_region_size + region_size_incr_step: $best_region_size"
        elif test $lt_best -eq 1
        then
            calc "$best_region_size - $region_size_incr_step" best_region_size
            if test $best_region_size -le 0
            then
                break
            fi
            info "best_region_size = best_region_size - region_size_incr_step: $best_region_size"
        else
            calc "$hbase_disk_ava_size / (($best_region_size + $region_size_incr_step) * $hdfs_replication)" next_region_size
            info "next_region_size: $next_region_size" 
            calc "$best_region_num - $next_region_size" tmp1
            calc "$best_region_num - $curr_region_size" tmp2
            info "next_best_internal: $tmp1"
            info "curr_best_interval: $tmp2"
            calc "$tmp1 > $tmp2" condition
            if test $condition -eq 1
            then
                break
            else
                calc "$best_region_size + $region_size_incr_step" best_region_size
                info "best_region_size = best_region_size + region_size_incr_step: $best_region_size"
            fi
        fi
    done

    info

    if test $best_region_size -ge 10
    then
        info "best_region_size: $best_region_size, max region number in per host: $curr_region_size"
    elif test $best_region_size -le 0
    then
        info "no best region size found, try to reduce the value of region_size_incr_step."
    else
        info "best_region_size: $best_region_size, it seems too small, suggest > 10"
    fi
    #hbase.hregion.max.filesize=$best_region_size
    #
    info
    info

    # bucketcache配置
    get_config javaheap_max_size
    get_config javaheap_min_size
    # hbase.hregion.memstore.flush.size=$memstore_flush_size
    # hbase.hregion.memstore.block.multiplier=3
    get_config memstore_flush_size
    # 这里调整,max_lower_limit也要调整
    get_config upper2lower_threds
    get_config max_lower_limit
    get_config min_lower_limit
    get_config javaheap_safaty_threds
    
    info "javaheap_max_size: $javaheap_max_size"
    info "javaheap_min_size: $javaheap_min_size"
    info "memstore_flush_size: $memstore_flush_size"
    info "upper2lower_threds: $upper2lower_threds"
    info "max_lower_limit: $max_lower_limit"
    info "min_lower_limit: $min_lower_limit"
    info "javaheap_safaty_threds: $javaheap_safaty_threds"
    info
    
    # lru配置
    get_config lru_memstore_threds
    get_config lru_blockcache_threds
    info "lru_memstore_threds: $lru_memstore_threds"
    info "lru_blockcache_threds: $lru_blockcache_threds"
    info
    
    # 经验值
    calc "$machine_memory * $machine_memory_ava_threds" machine_memory_ava_size
    get_config hbase_memory_ava_threds
    calc "$machine_memory_ava_size * $hbase_memory_ava_threds" hbase_memory_ava_size
    get_config javaheap_ava_threds
    calc "$hbase_memory_ava_size * $javaheap_ava_threds" best_javaheap
    info "machine_memory: $machine_memory"
    info "machine_memory_ava_threds: $machine_memory_ava_threds"
    info "machine_memory_ava_size: $machine_memory_ava_size"
    info "hbase_memory_ava_size: $hbase_memory_ava_size"
    info "javaheap_ava_threds: $javaheap_ava_threds"
    info "init best_javaheap: $best_javaheap"
    
    calc "$best_javaheap > $javaheap_max_size" heap_gt_max
    calc "$best_javaheap >= $javaheap_min_size" heap_gt_min
    
    mode=""
    if test $heap_gt_min -eq 1
    then
        info "use BucketCache mode."
        mode="bucketcache"
        # BucketCache模式
        if test $heap_gt_max -eq 1
        then
            best_javaheap=$javaheap_max_size
        else
            best_javaheap=$best_javaheap
        fi
        info "adjust best_javaheap to: $best_javaheap"
        calc "$hbase_disk_ava_size / ($best_region_size * 1024 / $memstore_flush_size * $hdfs_replication * 2)" xy
        info "JavaHeap * lowerLimit: $xy"
        calc "$xy / $best_javaheap" best_lower_limit
        info "init best_lower_limit: $best_lower_limit"
        calc "$best_lower_limit > $max_lower_limit" lower_gt_max
        calc "$best_lower_limit < $min_lower_limit" lower_lt_min
        if test $lower_gt_max -eq 1
        then
            best_lower_limit=$max_lower_limit
            calc "$xy / $best_lower_limit" best_javaheap
            info "current best_lower_limit great then max_lower_limit, reduce to $best_lower_limit, best_javaheap: $best_javaheap"
        elif test $lower_lt_min -eq 1
        then
            best_lower_limit=$min_lower_limit
            calc "$xy / $best_lower_limit" best_javaheap
            info "current best_lower_limit less then min_lower_limit, increase to $best_lower_limit, best_javaheap: $best_javaheap"
        else
            best_lower_limit=$best_lower_limit
            info "current best_lower_limit: $best_lower_limit, best_javaheap: $best_javaheap"
        fi
        # RegionServer JavaHeap=$best_javaheap
        # hbase.regionserver.global.memstore.upperLimit=$best_upper_limit
        # hbase.regionserver.global.memstore.lowerLimit=$best_lower_limit
        calc "$best_lower_limit + ($best_lower_limit * $upper2lower_threds)" best_upper_limit
        calc "$best_javaheap * $javaheap_safaty_threds" javaheap_safety_size
        calc "$best_javaheap * $best_upper_limit" javaheap_memstore_size
        calc "$javaheap_safety_size - $javaheap_memstore_size" javaheap_lrublock_size
        # hbase.bucketcache.size=$offheap_bucket_size
        calc "$hbase_memory_ava_size - $best_javaheap" offheap_bucket_size
        # hbase.bucketcache.percentage.in.combinedcache=$offheap_combined_threds
        calc "1 - ($javaheap_lrublock_size / $offheap_bucket_size)" offheap_combined_threds
        # hbase.bucketcache.ioengine=$offheap_bucket_ioengine
        offheap_bucket_ioengine="offheap"
        # hfile.block.cache.size=$javaheap_lru_blockcache_threds
        calc "$javaheap_safaty_threds - $best_upper_limit" javaheap_lru_blockcache_threds
    else
        # LRU模式
        info "current memory for hbase to use is too small, suggest to LRUBlockCache mode."
        mode="lru"
        calc "$hbase_memory_ava_size * $javaheap_safaty_threds" best_javaheap
        # hbase.regionserver.global.memstore.upperLimit=$best_upper_limit
        best_upper_limit=$lru_memstore_threds
        # hbase.regionserver.global.memstore.lowerLimit=$best_lower_limit
        calc "$best_upper_limit - ($best_upper_limit * $upper2lower_threds)" best_lower_limit
        # hfile.block.cache.size=$javaheap_lru_blockcache_threds
        javaheap_lru_blockcache_threds=$lru_blockcache_threds
    fi

    info 
    
    gc_config="
    -XX:+UseG1GC\n
    -XX:InitiatingHeapOccupancyPercent=65\n
    -XX:-ResizePLAB\n
    -XX:MaxGCPauseMillis=90 \n
    -XX:+UnlockDiagnosticVMOptions\n
    -XX:+G1SummarizeConcMark\n
    -XX:+ParallelRefProcEnabled\n
    -XX:G1HeapRegionSize=32m\n
    -XX:G1HeapWastePercent=20\n
    -XX:ConcGCThreads=4\n
    -XX:ParallelGCThreads=16 \n
    -XX:MaxTenuringThreshold=1\n
    -XX:G1MixedGCCountTarget=64\n
    -XX:+UnlockExperimentalVMOptions\n
    -XX:G1NewSizePercent=2\n
    -XX:G1OldCSetRegionThresholdPercent=5\n
    "
    basic_config="
    hbase.master.handler.count=256\n\
    hbase.regionserver.handler.count=256\n\
    hbase.client.retries.number=3\n\
    hbase.rpc.timeout=5000\n\
    hbase.hstore.blockingStoreFiles=100\n\
    hbase.regionserver.regionSplitLimit=0\n\
    "
    if test $mode == "lru"
    then
        hbase_config_result="
    RegionServer JavaHeap Size: $best_javaheap\n\
    hbase.hregion.max.filesize=$best_region_size\n\
    hbase.hregion.memstore.flush.size=$memstore_flush_size\n\
    hbase.hregion.memstore.block.multiplier=3\n\
    hbase.regionserver.global.memstore.upperLimit=$best_upper_limit\n\
    hbase.regionserver.global.memstore.lowerLimit=$best_lower_limit\n\
    hfile.block.cache.size=$javaheap_lru_blockcache_threds\n\
    $basic_config

    HBase RegionServer Java Configuration:\n
    $gc_config
    "
    else
        hbase_config_result="
    RegionServer JavaHeap Size: $best_javaheap\n\
    hbase.hregion.max.filesize=$best_region_size\n\
    hbase.hregion.memstore.flush.size=$memstore_flush_size\n\
    hbase.hregion.memstore.block.multiplier=3\n\
    hbase.regionserver.global.memstore.upperLimit=$best_upper_limit\n\
    hbase.regionserver.global.memstore.lowerLimit=$best_lower_limit\n\
    hbase.bucketcache.size=$offheap_bucket_size\n\
    hbase.bucketcache.ioengine=offheap\n\
    hbase.bucketcache.percentage.in.combinedcache=$offheap_combined_threds\n\
    hfile.block.cache.size=$javaheap_lru_blockcache_threds\n\

    HBase RegionServer Java Configuration:\n
    $gc_config
    "
    fi
    # 保存配置结果
    save "$hbase_config_result"
    info "hbase config_result:$hbase_config_result"
}

function yarn_config {
    info "Getting Yarn Configuration..."
    info
    save "####Yarn Configuration####"

    # 
    get_config yarn_core_ava_threds
    get_config yarn_memory_ava_threds
    # yarn.nodemanager.resource.memory-mb=$yarn_nm_memory
    calc "$machine_memory * $yarn_memory_ava_threds" yarn_nm_memory
    # yarn.app.mapreduce.am.resource.cpu-vcores=$yarn_nm_cores
    calc "$machine_cores * $yarn_core_ava_threds" yarn_nm_cores
    # yarn.scheduler.minimum-allocation-mb=$yarn_container_min_memory
    get_config yarn_container_min_memory
    # yarn.scheduler.maximum-allocation-mb=$yarn_container_max_memory
    get_config yarn_container_max_memory
    # yarn.scheduler.minimum-allocation-vcores=$yarn_container_min_cores
    get_config yarn_container_min_cores
    # yarn.scheduler.maximum-allocation-vcores=$yarn_container_max_cores
    get_config yarn_container_max_cores

    yarn_config_result="
    Service Monitor Client Configuration: <property><name>mapreduce.output.fileoutputformat.compress</name><value>true</value></property><property><name>mapreduce.output.fileoutputformat.compress.codec</name><value>org.apache.hadoop.io.compress.SnappyCodec</value></property><property><name>io.compression.codecs</name><value>org.apache.hadoop.io.compress.DefaultCodec,org.apache.hadoop.io.compress.GzipCodec,org.apache.hadoop.io.compress.BZip2Codec,org.apache.hadoop.io.compress.DeflateCodec,org.apache.hadoop.io.compress.SnappyCodec,org.apache.hadoop.io.compress.Lz4Codec</value></property>\n\
    
    Yarn Service Mapreduce Advanced Configuration Code Snippet: <property><name>mapreduce.map.output.compress</name><value>true</value></property><property><name>mapred.map.output.compress.codec</name><value>org.apache.hadoop.io.compress.SnappyCodec</value></property>\n\
    
    mapreduce.output.fileoutputformat.compress=enable\n\
    mapreduce.output.fileoutputformat.compress.type=BLOCK\n\
    mapreduce.output.fileoutputformat.compress.codec=org.apache.hadoop.io.compress.SnappyCodec\n\
    mapreduce.map.output.compress.codec=org.apache.hadoop.io.compress.SnappyCodec\n\
    mapreduce.map.output.compress=enable\n\
    zlib.compress.level=DEFAULT_COMPRESSION\n\
    yarn.nodemanager.resource.memory-mb=$yarn_nm_memory\n\
    yarn.app.mapreduce.am.resource.cpu-vcores=$yarn_nm_cores\n\
    yarn.scheduler.minimum-allocation-mb=$yarn_container_min_memory\n\
    yarn.scheduler.maximum-allocation-mb=$yarn_container_max_memory\n\
    yarn.scheduler.minimum-allocation-vcores=$yarn_container_min_cores\n\
    yarn.scheduler.maximum-allocation-vcores=$yarn_container_max_cores\n\
    "
    save "$yarn_config_result"
    info "yarn config_result:$yarn_config_result"
}

function spark_config {
    info "Getting Spark Configuration..."
    info
    save "####Spark Configuration####"

    spark_config_result="
    spark-conf/spark-defaults.conf Spark Client Configuration Code Snippet: \n\
    spark.driver.extraJavaOptions=-Dfile.encoding=UTF-8\n\
    spark.executor.extraJavaOptions=-Dfile.encoding=UTF-8\n\
    spark.hadoop.mapred.output.compress=true\n\
    spark.hadoop.mapred.output.compression.codec=org.apache.hadoop.io.compress.SnappyCodec\n\
    spark.hadoop.mapred.output.compression.type=BLOCK\n\

    spark2-conf/spark-env.sh Client Advanced Configuration Code Snippet: \n\
    PYSPARK_PYTHON=/usr/bin/python3.6\n\
    "

    save "$spark_config_result"
    info "spark config_result:$spark_config_result"
}

function kafka_config {
    info "Getting Kafka Configuration..."
    info
    save "####Kafka Configuration####"

    # num.partitions=$num_partitions
    get_config num_partitions
    kafka_config_result="
    num.partitions=$num_partitions
    "

    save "$kafka_config_result"
    info "kafka config_result:$kafka_config_result"
}

function hue_config {
    info "Getting Hue Configuration..."
    info
    save "####Hue Configuration####"

    hue_config_result="
    hue_safety_value.ini:\n\
    [impala]\n\
    server_host=\n\
    server_port=\n\

    impala Service: Impala\n\
    "

    save "$hue_config_result"
    info "hue config_result:$hue_config_result"
}

SELF=$(cd $(dirname $0) && pwd)
cd $SELF
init_config $SELF/deploy_config.cnf
get_config machine_disk
get_config machine_disk_ava_threds
get_config machine_memory
get_config machine_memory_ava_threds
get_config machine_cores

if [ $type == "hdfs" ]
then
    hdfs_config
elif [ $type == "hbase" ]
then
    hbase_config
elif [ $type == "yarn" ]
then
    yarn_config
elif [ $type == "spark" ]
then
    spark_config
elif [ $type == "kafka" ]
then
    kafka_config
elif [ $type == "hue" ]
then
    hue_config
elif [ $type == "all" ]
then
    hdfs_config
    hbase_config
    yarn_config
    spark_config
    kafka_config
    hue_config
else
    info "nothing todo, exit... \n try to use hdfs/hbase/yarn/spark/kafka/hue/all ?"
fi








