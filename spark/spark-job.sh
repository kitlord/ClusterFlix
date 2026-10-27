#!/usr/bin/env bash
exec /opt/spark/bin/spark-submit \
  --master spark://spark-master:7077 \
  --deploy-mode client \
  --class cinematch.Recommender \
  --conf spark.executor.memory=1g \
  --conf spark.driver.memory=1g \
  --conf spark.sql.shuffle.partitions=8 \
  --conf spark.mongodb.write.connection.uri=mongodb://mongo:27017/cinematch \
  --conf spark.mongodb.read.connection.uri=mongodb://mongo:27017/cinematch \
  --jars /spark/lib/mongo-spark-connector_2.12-10.4.0.jar,/spark/lib/mongodb-driver-sync-5.1.1.jar,/spark/lib/mongodb-driver-core-5.1.1.jar,/spark/lib/bson-5.1.1.jar,/spark/lib/bson-record-codec-5.1.1.jar \
  /spark/target/scala-2.12/cinematch_2.12-1.0.0.jar
