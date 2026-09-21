ThisBuild / version := "1.0.0"

lazy val root = (project in file("."))
  .settings(
    name := "cinematch",
    scalaVersion := "2.12.18",
    libraryDependencies ++= Seq(
      // Provided: Spark ships these at runtime; we only need them to compile.
      "org.apache.spark"  %% "spark-core"           % "3.5.1" % Provided,
      "org.apache.spark"  %% "spark-sql"            % "3.5.1" % Provided,
      "org.apache.spark"  %% "spark-mllib"          % "3.5.1" % Provided,
      // Connector is injected at submit time via --packages (scripts/train.sh).
      "org.mongodb.spark" %% "mongo-spark-connector" % "10.4.0" % Provided
    )
  )
