package cinematch

import org.apache.spark.ml.evaluation.RegressionEvaluator
import org.apache.spark.ml.recommendation.ALS
import org.apache.spark.sql.expressions.Window
import org.apache.spark.sql.functions._
import org.apache.spark.sql.SparkSession

object Recommender {
  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder.appName("CineMatch Recommender").getOrCreate()
    import spark.implicits._

    val ratings = spark.read.option("header", "true")
      .schema("userId INT, movieId INT, rating FLOAT, ts LONG")
      .csv("hdfs://namenode:9000/data/raw/ratings")
      .as[Rating]

    val rawFeedback = spark.read.format("mongodb")
      .option("collection", "user_ratings").load()
    val feedback =
      if (rawFeedback.columns.contains("userId"))
        rawFeedback.select(
          col("userId").cast("int"), col("movieId").cast("int"),
          col("rating").cast("float"), col("ts").cast("long"))
      else spark.emptyDataset[Rating].toDF()
    println(s"[CineMatch] HDFS ratings: ${ratings.count()}, feedback: ${feedback.count()}")

    val allRatings = ratings.toDF().unionByName(feedback)
      .withColumn("rk", row_number().over(
        Window.partitionBy("userId", "movieId").orderBy(col("ts").desc)))
      .filter(col("rk") === 1).drop("rk").as[Rating]

    val Array(train, test) = allRatings.randomSplit(Array(0.8, 0.2), seed = 42L)
    val model = new ALS().setRank(10).setMaxIter(10).setRegParam(0.1)
      .setUserCol("userId").setItemCol("movieId").setRatingCol("rating")
      .setColdStartStrategy("drop").fit(train)

    val rmse = new RegressionEvaluator().setMetricName("rmse").setLabelCol("rating")
      .setPredictionCol("prediction").evaluate(model.transform(test))
    println(f"[CineMatch] test RMSE = $rmse%.4f")
    Seq(f"test RMSE = $rmse%.4f").toDF("rmse").coalesce(1)
      .write.mode("overwrite").text("hdfs://namenode:9000/output/rmse")

    val movies = spark.read.option("header", "true")
      .schema("movieId INT, title STRING, genres STRING")
      .csv("hdfs://namenode:9000/data/raw/movies")
    val rated = allRatings.toDF().join(movies, Seq("movieId"), "left")

    val userCounts = allRatings.groupBy("userId").agg(count(lit(1)).as("ratedCount"))
    val userGenres = rated
      .select(col("userId"), explode(split(col("genres"), "\\|")).as("genre"))
      .filter(col("genre") =!= "(no genres listed)")
      .groupBy("userId", "genre").agg(count(lit(1)).as("n"))
      .withColumn("rk", row_number().over(
        Window.partitionBy("userId").orderBy(col("n").desc, col("genre"))))
      .filter(col("rk") <= 3)
      .groupBy("userId")
      .agg(array_sort(collect_list(struct(col("rk"), col("genre")))).as("ranked"))
      .select(col("userId"), transform(col("ranked"), g => g.getField("genre")).as("topGenres"))
    val userHigh = rated
      .withColumn("rk", row_number().over(
        Window.partitionBy("userId").orderBy(col("rating").desc, col("ts").desc)))
      .filter(col("rk") <= 5)
      .groupBy("userId")
      .agg(array_sort(collect_list(struct(
        col("rk"), col("title"), col("rating").as("userRating"), col("genres")))).as("ranked"))
      .select(col("userId"), transform(col("ranked"),
        m => struct(m.getField("title"), m.getField("userRating"), m.getField("genres"))).as("highRated"))

    val watchedIds = allRatings.select(col("userId"), col("movieId"))
    val top10 = model.transform(allRatings.select("userId").distinct().crossJoin(movies.select("movieId")))
      .select(col("userId"), col("movieId"), col("prediction").as("predictedRating"))
      .join(watchedIds, Seq("userId", "movieId"), "left_anti")
      .withColumn("rk", row_number().over(
        Window.partitionBy("userId").orderBy(col("predictedRating").desc)))
      .filter(col("rk") <= 10).drop("rk")

    val recommendations = top10.join(movies, Seq("movieId"), "left")
      .groupBy("userId")
      .agg(collect_list(struct(
        col("movieId"), col("title"), col("genres"), col("predictedRating"))).as("recommendations"))
      .join(userCounts, Seq("userId"))
      .join(userGenres, Seq("userId"))
      .join(userHigh, Seq("userId"))
    println(s"[CineMatch] writing ${recommendations.count()} users to MongoDB")
    recommendations.write.format("mongodb").mode("overwrite")
      .option("collection", "recommendations").save()

    val movieStats = allRatings.groupBy("movieId")
      .agg(count(lit(1)).as("numRatings"), avg("rating").as("avgRating"))
      .join(movies, Seq("movieId"), "left")
      .select("movieId", "title", "genres", "numRatings", "avgRating")
    movieStats.write.mode("overwrite").parquet("hdfs://namenode:9000/data/processed/movie_stats")

    movieStats.orderBy(desc("numRatings")).limit(50)
      .write.format("mongodb").mode("overwrite")
      .option("collection", "catalog").save()

    spark.stop()
  }

  case class Rating(userId: Int, movieId: Int, rating: Float, ts: Long)
}
