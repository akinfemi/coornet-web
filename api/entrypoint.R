#!/usr/bin/env Rscript
# Start the API:  Rscript api/entrypoint.R   (from the repo root)
# Env: DATA_DIR, PORT, MAX_UPLOAD_MB, MAX_ROWS, MAX_GROUP_SIZE,
#      MAX_CONCURRENT_JOBS, JOB_TIMEOUT_S, RETENTION_HOURS, ALLOWED_ORIGINS

args <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", grep("^--file=", args, value = TRUE))
API_ROOT <- if (length(script) == 1) dirname(normalizePath(script)) else "api"

source(file.path(API_ROOT, "plumber.R"))

jobs_schedule_tick()

port <- as.integer(Sys.getenv("PORT", "8000"))
message(sprintf("coortweet-api listening on :%d (DATA_DIR=%s)", port, data_dir()))
plumber::pr_run(build_api(), host = "0.0.0.0", port = port, quiet = TRUE)
