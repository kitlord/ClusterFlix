"""CineMatch web UI: per-user ALS recommendations and Hive reports."""
import csv
import os

from flask import Flask, render_template, request
from pymongo import MongoClient

app = Flask(__name__)

client = MongoClient(os.environ.get("MONGO_URI", "mongodb://mongo:27017"))
db = client["cinematch"]

REPORT_DIR = os.environ.get("REPORT_DIR", "/report")
# (slug, title, csv columns) - the Hive export contains data rows only.
REPORTS = [
    ("most_rated", "Most-rated movies", ["title", "num_ratings"]),
    ("avg_rating_by_genre", "Average rating by genre", ["genre", "avg_rating", "num_ratings"]),
    ("rating_distribution", "Rating distribution", ["rating", "num_ratings"]),
]


def load_report(slug, header):
    """Return (header, rows) for a report CSV, or None if not generated yet."""
    path = os.path.join(REPORT_DIR, f"{slug}.csv")
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        return None
    with open(path, newline="", encoding="utf-8") as fh:
        rows = [row for row in csv.reader(fh) if row]
    if not rows:
        return None
    return header, rows


@app.route("/")
def index():
    user_ids = sorted(doc["userId"] for doc in db.recommendations.find({}, {"userId": 1}))

    selected = request.args.get("user_id", type=int)
    if selected is None and user_ids:
        selected = user_ids[0]

    doc = db.recommendations.find_one({"userId": selected}) if selected is not None else None
    recs = []
    if doc:
        recs = sorted(doc.get("recommendations", []),
                      key=lambda r: -r.get("predictedRating", 0.0))

    return render_template("index.html", user_ids=user_ids, selected=selected, recs=recs)


@app.route("/reports")
def reports():
    data = [(label, load_report(slug, header)) for slug, label, header in REPORTS]
    return render_template("reports.html", reports=data)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
