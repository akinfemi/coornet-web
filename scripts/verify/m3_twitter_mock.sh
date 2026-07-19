#!/usr/bin/env bash
# M3 verification: full Twitter import flow against a local mock X API —
# import job -> dataset materialized -> analysis job on the imported dataset.
# Also asserts the bearer token never reaches disk.
set -euo pipefail
PORT="${PORT:-8011}"
MOCK_PORT="${MOCK_PORT:-8021}"
DATA_DIR="$(mktemp -d)"
BASE="http://localhost:$PORT/api/v1"
cleanup() { kill "${API_PID:-}" "${MOCK_PID:-}" 2>/dev/null || true; rm -rf "$DATA_DIR"; }
trap cleanup EXIT

# Mock X API: two pages of retweet-shaped results.
Rscript - "$MOCK_PORT" <<'EOF' &
suppressMessages(library(plumber))
port <- as.integer(commandArgs(trailingOnly = TRUE)[1])
mk_tweet <- function(id, author, created, rt = NULL) {
  t <- list(id = id, author_id = author, created_at = created)
  if (!is.null(rt)) t$referenced_tweets <- list(list(type = "retweeted", id = rt))
  t
}
page1 <- list(
  data = list(
    mk_tweet("o1", "seed", "2024-05-01T10:00:00.000Z"),
    mk_tweet("r1", "acct_a", "2024-05-01T10:00:03.000Z", rt = "o1"),
    mk_tweet("r2", "acct_b", "2024-05-01T10:00:05.000Z", rt = "o1")
  ),
  meta = list(result_count = 3, next_token = "page2tok")
)
page2 <- list(
  data = list(
    mk_tweet("r3", "acct_c", "2024-05-01T10:00:08.000Z", rt = "o1"),
    mk_tweet("r4", "acct_a", "2024-05-01T10:01:00.000Z", rt = "o2"),
    mk_tweet("r5", "acct_b", "2024-05-01T10:01:04.000Z", rt = "o2")
  ),
  meta = list(result_count = 3)
)
pr() |>
  pr_set_serializer(serializer_unboxed_json()) |>
  pr_get("/2/tweets/search/recent", function(req) {
    if (identical(req$argsQuery$next_token, "page2tok")) page2 else page1
  }) |>
  pr_run(host = "127.0.0.1", port = port, quiet = TRUE)
EOF
MOCK_PID=$!

DATA_DIR="$DATA_DIR" PORT="$PORT" TWITTER_API_BASE_URL="http://127.0.0.1:$MOCK_PORT/2" \
  Rscript api/entrypoint.R &
API_PID=$!

for _ in $(seq 1 30); do curl -sf "$BASE/healthz" >/dev/null 2>&1 && break; sleep 1; done
curl -sf "$BASE/healthz" >/dev/null || { echo "API failed to start"; exit 1; }

RESP=$(curl -sf -X POST "$BASE/twitter/import" -H 'Content-Type: application/json' -d '{
  "bearer_token": "TEST-SECRET-TOKEN-XYZ",
  "mode": "search_recent",
  "query": "#anything",
  "intent": "retweets",
  "max_results": 100
}')
JOB=$(echo "$RESP" | python3 -c 'import sys,json;print(json.load(sys.stdin)["job_id"])')
DS=$(echo "$RESP" | python3 -c 'import sys,json;print(json.load(sys.stdin)["dataset_id"])')

for _ in $(seq 1 30); do
  S=$(curl -sf "$BASE/jobs/$JOB" | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"])')
  [ "$S" = "succeeded" ] && break
  [ "$S" = "failed" ] && { curl -s "$BASE/jobs/$JOB"; exit 1; }
  sleep 1
done
[ "$S" = "succeeded" ] || { echo "import did not finish"; exit 1; }

# Expected rows: 5 retweets + originals rule (o1 present in collection -> +1). o2 absent.
N_ROWS=$(Rscript -e "cat(nrow(readRDS(file.path('$DATA_DIR','datasets','$DS','mapped.rds'))))")
[ "$N_ROWS" = "6" ] || { echo "expected 6 mapped rows (5 RTs + 1 original), got $N_ROWS"; exit 1; }
echo "import mapped rows: $N_ROWS (originals rule applied) OK"

# Token must not exist anywhere on disk.
if grep -r "TEST-SECRET-TOKEN-XYZ" "$DATA_DIR" >/dev/null 2>&1; then
  echo "TOKEN LEAKED TO DISK"; exit 1
fi
echo "token redaction on disk: OK"

# The imported dataset feeds a normal analysis job.
AJOB=$(curl -sf -X POST "$BASE/jobs" -H 'Content-Type: application/json' \
  -d "{\"dataset_id\":\"$DS\",\"params\":{\"time_window\":60,\"min_participation\":1,\"edge_weight\":0.5}}" \
  | python3 -c 'import sys,json;print(json.load(sys.stdin)["job_id"])')
for _ in $(seq 1 30); do
  S=$(curl -sf "$BASE/jobs/$AJOB" | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"])')
  [ "$S" = "succeeded" ] && break
  [ "$S" = "failed" ] && { curl -s "$BASE/jobs/$AJOB"; exit 1; }
  sleep 1
done
[ "$S" = "succeeded" ] || { echo "analysis on imported data did not finish"; exit 1; }
N_NODES=$(curl -sf "$BASE/jobs/$AJOB/network" | python3 -c 'import sys,json;print(json.load(sys.stdin)["meta"]["n_nodes"])')
echo "analysis on imported dataset: $N_NODES nodes OK"

echo "M3 VERIFY PASSED"
