#!/usr/bin/env bash
# M1 verification: drive the HTTP API with the russian_coord_tweets fixture and
# compare the resulting network against a direct in-R run (vignette params).
# Usage: API must be running (Rscript api/entrypoint.R). PORT env overrides.
set -euo pipefail
PORT="${PORT:-8010}"
BASE="http://localhost:$PORT/api/v1"
FIXTURE="api/tests/fixtures/russian_coord_tweets.csv"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -f "$FIXTURE" ] || Rscript api/scripts/export_fixtures.R

curl -sf "$BASE/healthz" > /dev/null || { echo "API not running on :$PORT"; exit 1; }

DS=$(curl -sf -F "file=@$FIXTURE" "$BASE/datasets" | python3 -c 'import sys,json;print(json.load(sys.stdin)["dataset_id"])')
curl -sf -X POST "$BASE/datasets/$DS/mapping" -H 'Content-Type: application/json' \
  -d '{"object_id":"object_id","account_id":"account_id","content_id":"content_id","timestamp_share":"timestamp_share"}' > /dev/null

JOB=$(curl -sf -X POST "$BASE/jobs" -H 'Content-Type: application/json' \
  -d "{\"dataset_id\":\"$DS\",\"params\":{\"time_window\":60,\"min_participation\":2,\"edge_weight\":0.5,\"subgraph\":1}}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["job_id"])')

for _ in $(seq 1 90); do
  S=$(curl -sf "$BASE/jobs/$JOB" | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"])')
  [ "$S" = "succeeded" ] && break
  [ "$S" = "failed" ] && { curl -s "$BASE/jobs/$JOB"; exit 1; }
  sleep 2
done
[ "$S" = "succeeded" ] || { echo "job did not finish in time"; exit 1; }

curl -sf "$BASE/jobs/$JOB/network" -o "$TMP/network.json"
curl -sf "$BASE/jobs/$JOB/export?format=graphml" -o "$TMP/graph.graphml"
curl -sf "$BASE/jobs/$JOB/export?format=gexf" -o "$TMP/graph.gexf"

Rscript - "$TMP/network.json" <<'EOF'
suppressMessages({library(CooRTweet); library(data.table); library(igraph); library(jsonlite)})
args <- commandArgs(trailingOnly = TRUE)
api <- fromJSON(args[1])
dt <- fread("api/tests/fixtures/russian_coord_tweets.csv")
for (col in c("object_id","account_id","content_id")) set(dt, j=col, value=as.character(dt[[col]]))
res <- detect_groups(dt, time_window = 60, min_participation = 2)
g <- generate_coordinated_network(res, edge_weight = 0.5, subgraph = 1)
stopifnot(api$meta$n_nodes == vcount(g), api$meta$n_edges == ecount(g))
edf <- igraph::as_data_frame(g, what = "edges")
key <- function(a, b) paste(pmin(a, b), pmax(a, b))
r_edges <- data.table(k = key(edf$from, edf$to), w = edf$weight, td = edf$avg_time_delta)
a_edges <- data.table(k = key(api$edges$source, api$edges$target),
                      w = api$edges$weight, td = api$edges$avg_time_delta)
setorder(r_edges, k); setorder(a_edges, k)
stopifnot(identical(r_edges$k, a_edges$k))
stopifnot(all(abs(r_edges$w - a_edges$w) < 1e-9))
stopifnot(all(abs(r_edges$td - a_edges$td) < 1e-6))
stopifnot(identical(sort(api$nodes$id), sort(V(g)$name)))
cat("GOLDEN OK:", vcount(g), "nodes,", ecount(g), "edges, edge sets and weights identical\n")
EOF

python3 - "$TMP/graph.graphml" "$TMP/graph.gexf" <<'EOF'
import sys, xml.etree.ElementTree as ET
for p in sys.argv[1:3]:
    ET.parse(p)
print("exports parse as XML: OK")
EOF

echo "M1 VERIFY PASSED (dataset $DS, job $JOB)"
