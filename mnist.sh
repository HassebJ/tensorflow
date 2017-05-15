#!/bin/bash
set o -xtrace
pushd ~/git-pull/finished/streaming-benchmarks/sbatch_spark_scripts/

ri-spark-basic-comet.sbatch iptof n
ssh -t -t head sudo /sbin/distribute_hosts.sh ~/myhostnames /home/javed.19/git-pull/finished/streaming-benchmarks/sbatch_spark_scripts/host_files/ib
ri-spark-basic-comet.sbatch config_spark
hadoop-script.sh 
popd

~/git-pull/finished/HiBench/hadoop-2.7.3/bin/hadoop fs -put /home/javed.19/tensorflow/ecosystem/hadoop/target/tensorflow-hadoop-1.0-SNAPSHOT-shaded-protobuf.jar /



~/git-pull/finished/HiBench/hadoop-2.7.3/bin/hadoop fs -put ${PYTHON_ROOT}/Python.zip /

export PYSPARK_PYTHON=${PYTHON_ROOT}/bin/python
export SPARK_YARN_USER_ENV="PYSPARK_PYTHON=Python/bin/python"
export PATH=${PYTHON_ROOT}/bin/:$PATH
export SPARK_HOME=/home/javed.19/git-pull/finished/HiBench/spark-2.0.2-bin-hadoop2.7

#unzip and put in hdfs
${SPARK_HOME}/bin/spark-submit \
--master yarn \
--deploy-mode cluster \
--num-executors 4 \
--executor-memory 6G \
--archives hdfs:///Python.zip#Python,mnist/mnist.zip#mnist \
--conf spark.executorEnv.LD_LIBRARY_PATH="/usr/local/cuda/lib64" \
--driver-library-path="/usr/local/cuda/lib64" \
TensorFlowOnSpark/examples/mnist/mnist_data_setup.py \
--output mnist/csv \
--format csv

#convert to TFRecords
${SPARK_HOME}/bin/spark-submit \
--master yarn \
--deploy-mode cluster \
--num-executors 4 \
--executor-memory 6G \
--archives hdfs:///Python.zip#Python,mnist/mnist.zip#mnist \
--jars hdfs:///tensorflow-hadoop-1.0-SNAPSHOT-shaded-protobuf.jar \
--conf spark.executorEnv.LD_LIBRARY_PATH="/usr/local/cuda/lib64" \
--driver-library-path="/usr/local/cuda/lib64" \
TensorFlowOnSpark/examples/mnist/mnist_data_setup.py \
--output mnist/tfr \
--format tfr

#start training
${SPARK_HOME}/bin/spark-submit \
--master yarn \
--deploy-mode cluster \
--num-executors 4 \
--executor-memory 7G \
--py-files TensorFlowOnSpark/tfspark.zip,TensorFlowOnSpark/examples/mnist/spark/mnist_dist.py \
--conf spark.dynamicAllocation.enabled=false \
--conf spark.yarn.maxAppAttempts=1 \
--archives hdfs:///Python.zip#Python \
--conf spark.executorEnv.LD_LIBRARY_PATH="/usr/local/cuda/lib64:$JAVA_HOME/jre/lib/amd64/server" \
--driver-library-path="/usr/local/cuda/lib64" \
TensorFlowOnSpark/examples/mnist/spark/mnist_spark.py \
--images mnist/csv/train/images \
--labels mnist/csv/train/labels \
--mode train \
--model mnist_model \
--rdma \
--tensorboard
