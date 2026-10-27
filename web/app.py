import csv
import os
import time
from urllib.parse import quote

import http.client
import json
import socket

from flask import Flask, redirect, render_template, request
from pymongo import MongoClient

app = Flask(__name__)
db = MongoClient(os.environ.get("MONGO_URI", "mongodb://mongo:27017"))["cinematch"]

SPARK_CONTAINER = os.environ.get("SPARK_CONTAINER", "spark-master")
DOCKER_SOCK = os.environ.get("DOCKER_SOCK", "/var/run/docker.sock")


class DockerSocket(http.client.HTTPConnection):
    def __init__(self):
        super().__init__("docker")

    def connect(self):
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(DOCKER_SOCK)
        self.sock = sock


def docker_exec(cid, cmd, detach):
    if isinstance(cmd, str):
        cmd = ["bash", "-c", cmd]
    conn = DockerSocket()
    conn.request("POST", f"/containers/{cid}/exec",
                 body=json.dumps({"Cmd": cmd, "AttachStdout": not detach,
                                  "AttachStderr": False, "Detach": detach}),
                 headers={"Content-Type": "application/json"})
    exec_id = json.loads(conn.getresponse().read())["Id"]
    conn.close()

    conn = DockerSocket()
    conn.request("POST", f"/exec/{exec_id}/start",
                 body=json.dumps({"Detach": detach}),
                 headers={"Content-Type": "application/json"})
    out = conn.getresponse().read()
    conn.close()
    return None if detach else out


def spark_master_id():
    filters = quote('{"name": ["%s"]}' % SPARK_CONTAINER)
    containers = json.loads(docker_request("GET", f"/containers/json?filters={filters}"))
    if len(containers) != 1:
        raise RuntimeError(f"expected 1 {SPARK_CONTAINER} container, found {len(containers)}")
    return containers[0]["Id"]


def docker_request(method, path, body=None):
    conn = DockerSocket()
    conn.request(method, path, body=json.dumps(body) if body is not None else None,
                 headers={"Content-Type": "application/json"})
    payload = conn.getresponse().read()
    conn.close()
    return payload


def training_running():
    out = docker_exec(spark_master_id(), "pgrep -f spark-submit", detach=False)
    return bool(out and out.strip())


def start_training():
    docker_exec(spark_master_id(), ["bash", "/spark/spark-job.sh"], detach=True)

REPORT_DIR = os.environ.get("REPORT_DIR", "/report")
REPORTS = [
    ("most_rated", "Most-rated movies", ["title", "num_ratings"]),
    ("avg_rating_by_genre", "Average rating by genre", ["genre", "avg_rating", "num_ratings"]),
    ("rating_distribution", "Rating distribution", ["rating", "num_ratings"]),
]


def load_report(slug, header):
    path = os.path.join(REPORT_DIR, f"{slug}.csv")
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return None
    with open(path, newline="", encoding="utf-8") as fh:
        rows = [row for row in csv.reader(fh) if row]
    return (header, rows) if rows else None


@app.route("/")
def index():
    user_ids = sorted(doc["userId"] for doc in db.recommendations.find({}, {"userId": 1}))
    selected = request.args.get("user_id", type=int) or (user_ids[0] if user_ids else None)
    doc = db.recommendations.find_one({"userId": selected}) if selected is not None else None

    recs = sorted(doc.get("recommendations", []), key=lambda r: -r.get("predictedRating", 0.0)) if doc else []
    history = {
        "rated_count": doc.get("ratedCount", 0),
        "top_genres": doc.get("topGenres", []),
        "high_rated": doc.get("highRated", []),
    } if doc else None
    stale = bool(doc.get("stale")) if doc else False

    watch_options = [{"movieId": r["movieId"], "title": r["title"]} for r in recs]
    if not watch_options:
        watch_options = list(db.catalog.find({}, {"_id": 0, "movieId": 1, "title": 1})
                             .sort("numRatings", -1).limit(20))

    return render_template("index.html", user_ids=user_ids, selected=selected,
                           recs=recs, history=history, stale=stale,
                           watch_options=watch_options)


@app.route("/newuser", methods=["POST"])
def newuser():
    top = db.recommendations.find_one(sort=[("userId", -1)]) or {}
    new_id = (top.get("userId") or 0) + 1
    db.recommendations.insert_one({
        "userId": new_id, "ratedCount": 0,
        "topGenres": [], "highRated": [], "recommendations": [],
    })
    return redirect(f"/?user_id={new_id}")


@app.route("/watch", methods=["POST"])
def watch():
    user_id = request.form.get("user_id", type=int)
    movie_id = request.form.get("movie_id", type=int)
    rating = request.form.get("rating", type=float)
    if user_id is None or movie_id is None or rating is None or not 0.5 <= rating <= 5.0:
        return "bad request", 400

    db.user_ratings.update_one(
        {"userId": user_id, "movieId": movie_id},
        {"$set": {"rating": rating, "ts": int(time.time())}},
        upsert=True,
    )
    db.recommendations.update_one({"userId": user_id}, {"$set": {"stale": True}})
    if not training_running():
        start_training()
    return redirect(f"/?user_id={user_id}")


@app.route("/reports")
def reports():
    data = [(label, load_report(slug, header)) for slug, label, header in REPORTS]
    return render_template("reports.html", reports=data)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
