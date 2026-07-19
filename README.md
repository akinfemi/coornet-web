# coornet-web

A public web app for detecting **coordinated behavior on social media**, built on the
[CooRTweet](https://cran.r-project.org/package=CooRTweet) R package (Righetti & Balluff,
2025) — the published implementation runs unmodified behind a REST API; nothing is
reimplemented.

- **R Plumber API** (`api/`) — upload CSV → map to the 4-column schema
  (`object_id`, `account_id`, `content_id`, `timestamp_share`) → detection jobs in
  isolated `callr` worker processes → network JSON / GraphML / GEXF / CSV.
- **React frontend** (`web/`) — wizard, interactive sigma.js coordination network
  (community colors, client-side edge-weight percentile slider, account stats),
  sortable tables, exports, and a guided walkthrough reproducing the papers' analyses.
- **Twitter/X connector** — bring-your-own-key import from the X API v2 (Basic tier+),
  mapped to the schema per intent (retweets / hashtags / urls / domains). Tokens are
  never persisted.

## Local development

```sh
# prerequisites: R (with packages — see below), Node 22+
git clone --recurse-submodules <repo>
R CMD INSTALL CooRTweet
Rscript -e 'install.packages(c("plumber","callr","jsonlite","uuid","httr2","later","ps","R.utils","data.table","tidytable","RcppSimdJson","lubridate","igraph","stringi"))'

# terminal 1 — API on :8010
DATA_DIR=$PWD/data-local PORT=8010 Rscript api/entrypoint.R

# terminal 2 — frontend on :5173 (proxies /api to :8010)
cd web && npm install && npm run dev
```

Walkthrough data (committed under `web/public/walkthrough/`) regenerates with
`Rscript api/scripts/build_walkthrough.R`.

## Tests

```sh
Rscript api/tests/run_tests.R          # unit: mappers, redaction, pagination
./scripts/verify/m1_api_golden.sh      # HTTP flow vs direct R run (API must be up)
./scripts/verify/m3_twitter_mock.sh    # import flow against a mock X API
cd web && npx playwright test          # e2e: wizard flow + walkthrough
```

The golden script asserts the API's network (edge sets, weights, time deltas) is
identical to running `detect_groups` + `generate_coordinated_network` directly in R.

## Docker / deployment

```sh
docker compose -f docker/docker-compose.yml up   # web on :8080
```

Fly.io: `fly deploy -c fly.api.toml` (2 GB volume-backed machine) and
`fly deploy -c fly.web.toml` (static + Caddy proxy; set `API_UPSTREAM` secret).
Env knobs: `MAX_UPLOAD_MB`, `MAX_ROWS`, `MAX_GROUP_SIZE`, `MAX_CONCURRENT_JOBS`,
`JOB_TIMEOUT_S`, `RETENTION_HOURS`, `RATE_LIMIT_POSTS_PER_HOUR`, `TWITTER_MAX_POSTS`.

## Data & privacy

Uploaded datasets and results auto-delete after `RETENTION_HOURS` (72 by default);
result URLs are unguessable UUIDs. X API bearer tokens live only in the import
request and worker memory — `params.json` is credential-redacted and verified by test.

## Papers

- Giglietto, Righetti, Rossi & Marino (2020). *It takes a village to manipulate the
  media.* Information, Communication & Society. (`papers/`)
- Giglietto, Marino, Mincigrucci & Stanziano (2023). *A workflow to detect, monitor,
  and update lists of coordinated social media accounts across time.* Social Media + Society. (`papers/`)
- Righetti & Balluff (2025). *CooRTweet: A Generalized R Software for Coordinated
  Network Detection.* Computational Communication Research.
