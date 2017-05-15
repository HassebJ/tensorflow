#!/bin/bash
#SBATCH --output="tfospark-basic-ri2.out"
#SBATCH --partition=gpu
#SBATCH --nodes=16
#SBATCH --export=ALL


#CIFAR
ri-spark-basic-comet.sbatch iptof n

ssh -t -t head sudo /sbin/distribute_hosts.sh ~/myhostnames /home/javed.19/git-pull/finished/streaming-benchmarks/sbatch_spark_scripts/host_files/ib


pushd ~/git-pull/finished/streaming-benchmarks/sbatch_spark_scripts/

ri-spark-basic-comet.sbatch config_spark

hadoop-script.sh 

popd

$HADOOP_HOME/bin/hadoop fs -put /home/javed.19/tensorflow/cifar-10-batches-py /
$HADOOP_HOME/bin/hadoop fs -put ${PYTHON_ROOT}/Python.zip /



# set environment variables (if not already done)
export PYTHON_ROOT=~/Python
export PYSPARK_PYTHON=${PYTHON_ROOT}/bin/python
export SPARK_YARN_USER_ENV="PYSPARK_PYTHON=Python/bin/python"
export PATH=${PYTHON_ROOT}/bin/:$PATH
export CIFAR10_DATA=hdfs:///cifar-10-batches-py


pushd ${TFoS_HOME}

SECONDS=0

export NUM_GPU=2
export MEMORY=$((NUM_GPU * 11))
${SPARK_HOME}/bin/spark-submit \
--master yarn \
--deploy-mode cluster \
--num-executors 448 \
--executor-memory ${MEMORY}G \
--py-files ${TFoS_HOME}/tfspark.zip,cifar10.zip \
--conf spark.dynamicAllocation.enabled=false \
--conf spark.yarn.maxAppAttempts=1 \
--archives hdfs:///Python.zip#Python \
--conf spark.executorEnv.LD_LIBRARY_PATH="/usr/local/cuda/lib64:$JAVA_HOME/jre/lib/amd64/server" \
--driver-library-path="/usr/local/cuda/lib64" \
${TFoS_HOME}/examples/cifar10/cifar10_multi_gpu_train.py \
--data_dir ${CIFAR10_DATA} \
--train_dir hdfs:///cifar10_train \
--max_steps 1000 \
--num_gpus ${NUM_GPU} \
--rdma \
--tensorboard

train_duration=$SECONDS
echo "$(($train_duration / 60)) minutes and $(($train_duration % 60)) seconds elapsed for training ." > ~/train_time.log
SECONDS=0

${SPARK_HOME}/bin/spark-submit \
--master yarn \
--deploy-mode cluster \
--num-executors 448 \
--executor-memory ${MEMORY}G \
--py-files ${TFoS_HOME}/tfspark.zip,cifar10.zip \
--conf spark.dynamicAllocation.enabled=false \
--conf spark.yarn.maxAppAttempts=1 \
--archives hdfs:///Python.zip#Python \
--conf spark.executorEnv.LD_LIBRARY_PATH="lib64:/usr/local/cuda/lib64:$JAVA_HOME/jre/lib/amd64/server" \
--driver-library-path="lib64:/usr/local/cuda/lib64" \
${TFoS_HOME}/examples/cifar10/cifar10_eval.py \
--data_dir ${CIFAR10_DATA} \
--eval_dir hdfs:///cifar10_eval \
--num_gpus ${NUM_GPU} \
--rdma \
--run_once


eval_duration=$SECONDS
echo "$(($eval_duration / 60)) minutes and $(($eval_duration % 60)) seconds elapsed for training ." > ~/eval_time.log
popd
