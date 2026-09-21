package cinematch

import org.apache.spark.ml.evaluation.RegressionEvaluator
import org.apache.spark.ml.recommendation.ALS
import org.apache.spark.sql.{DataFrame, SparkSession}
import org.apache.spark.sql.functions._

/**
 * CineMatch training job.
 *
 * ratings.csv + movies.csv from HDFS
 *   -> 80/20 train/test split
 *   -> ALS model (MLlib), test RMSE
 *   -> top-10 recommendations per user, joined with titles/genres -> MongoDB
 *   -> per-movie statistics -> Parquet in HDFS
 */
object Recommender {

  val HdfsUrl: String = sys.env.getOrElse("CINEMATCH_HDFS", "hdfs://namenode:9000")

  def main(args: Array[String]): Unit = {
    val spark = SparkSession.builder
      .appName("CineMatch Recommender")
      .getOrCreate()

    try {
      import spark.implicits._

      val ratings = spark.read
        .option("header", "true")
        .schema("userId INT, movieId INT, rating FLOAT, ts LONG")
        .csv(s"$HdfsUrl/data/raw/ratings")
        .as[Rating]

      println(s"[CineMatch] loaded ${ratings.count()} ratings")
      println(s"[CineMatch] distinct users: ${ratings.select("userId").distinct().count()}")

      // ---------------- 1. split + train + evaluate ----------------
      val Array(train, test) = ratings.randomSplit(Array(0.8, 0.2), seed = 42L)
      println(s"[CineMatch] train=${train.count()} test=${test.count()}")

      val als = new ALS()
        .setRank(10)
        .setMaxIter(10)
        .setRegParam(0.1)
        .setUserCol("userId")
        .setItemCol("movieId")
        .setRatingCol("rating")
        .setColdStartStrategy("drop") // drop NaN predictions in evaluation

      println("[CineMatch] fitting ALS model...")
      val model = als.fit(train)

      val rmse = new RegressionEvaluator()
        .setMetricName("rmse")
        .setLabelCol("rating")
        .setPredictionCol("prediction")
        .evaluate(model.transform(test))
      println(f"[CineMatch] test RMSE = $rmse%.4f")

      // single text file, safe to re-run (overwrite instead of saveAsTextFile)
      Seq(f"test RMSE = $rmse%.4f")
        .toDF("rmse")
        .coalesce(1)
        .write
        .mode("overwrite")
        .text(s"$HdfsUrl/output/rmse")

      // ---------------- 2. top-10 recommendations per user ----------------
      val movies = spark.read
        .option("header", "true")
        .schema("movieId INT, title STRING, genres STRING")
        .csv(s"$HdfsUrl/data/raw/movies")

      val top10 = model.recommendForAllUsers(10)
        .withColumn("rec", explode(col("recommendations")))
        .select(
          col("userId"),
          col("rec.movieId").as("movieId"),
          col("rec.rating").as("predictedRating"))

      val recommendations = joinTitles(top10, movies)
        .groupBy("userId")
        .agg(collect_list(
          struct(col("movieId"), col("title"), col("genres"), col("predictedRating"))
        ).as("recommendations"))

      println("[CineMatch] writing recommendations to MongoDB (cinematch.recommendations)...")
      recommendations.write
        .format("mongodb")
        .mode("overwrite")
        .option("collection", "recommendations")
        .save()
      println(s"[CineMatch] wrote ${recommendations.count()} users' recommendations")

      // ---------------- 3. basic movie statistics -> Parquet ----------------
      val stats = ratings
        .groupBy("movieId")
        .agg(count(lit(1)).as("numRatings"), avg("rating").as("avgRating"))

      val movieStats = joinTitles(stats, movies)
        .select("movieId", "title", "genres", "numRatings", "avgRating")

      println(s"[CineMatch] writing ${movieStats.count()} movie stats to $HdfsUrl/data/processed/movie_stats")
      movieStats.write
        .mode("overwrite")
        .parquet(s"$HdfsUrl/data/processed/movie_stats")

      println("[CineMatch] done")
    } finally {
      spark.stop()
    }
  }

  private def joinTitles(df: DataFrame, movies: DataFrame): DataFrame =
    df.join(movies, Seq("movieId"), "left")

  case class Rating(userId: Int, movieId: Int, rating: Float, ts: Long)
}
