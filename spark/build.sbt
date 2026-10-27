ThisBuild / version := "1.0.0"

lazy val root = (project in file("."))
  .settings(
    name := "cinematch",
    scalaVersion := "2.12.18",
    libraryDependencies ++= Seq(
      "org.apache.spark"  %% "spark-core"           % "3.5.1"  % Provided,
      "org.apache.spark"  %% "spark-sql"            % "3.5.1"  % Provided,
      "org.apache.spark"  %% "spark-mllib"          % "3.5.1"  % Provided,
      "org.mongodb.spark" %% "mongo-spark-connector" % "10.4.0" % Provided
    )
  )
