# Job registry + queue. The plumber process never does heavy work: jobs run
# in callr::r_bg children, launched from a `later` tick that also enforces
# timeouts and runs the TTL sweeper. status.json in each job dir is the
# durable source of truth; the in-memory registry only tracks live processes.

.jobs <- new.env(parent = emptyenv())

jobs_max_concurrent <- function() cfg_num("MAX_CONCURRENT_JOBS", 2)
jobs_timeout_s <- function() cfg_num("JOB_TIMEOUT_S", 900)

job_create <- function(dataset_id, params, type = "analysis", extra = list()) {
  id <- new_id()
  dir.create(job_dir(id), recursive = TRUE)
  record <- c(list(
    job_id = id,
    type = type,
    dataset_id = dataset_id,
    params = params,
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ), extra)
  write_json_file(record, file.path(job_dir(id), "params.json"))
  write_json_file(
    list(status = "queued", stage = "queued"),
    file.path(job_dir(id), "status.json")
  )
  assign(id, list(
    id = id, type = type, dataset_id = dataset_id, params = params,
    status = "queued", process = NULL, started_at = NULL,
    queued_at = Sys.time(), extra = extra
  ), envir = .jobs)
  id
}

job_status <- function(id) {
  st <- read_json_file(file.path(job_dir(id), "status.json"))
  if (is.null(st)) return(NULL)
  entry <- if (exists(id, envir = .jobs)) get(id, envir = .jobs) else NULL
  # A job whose process died without writing a terminal status crashed hard
  # (segfault/OOM) — surface that rather than a stuck "running".
  if (!is.null(entry) && !is.null(entry$process) && !entry$process$is_alive() &&
      !st$status %in% c("succeeded", "failed")) {
    err_tail <- tryCatch(
      paste(utils::tail(readLines(file.path(job_dir(id), "worker.log"), warn = FALSE), 5), collapse = "\n"),
      error = function(e) ""
    )
    st <- list(status = "failed", stage = "crashed",
               error = paste("worker process exited unexpectedly.", err_tail))
    write_json_file(st, file.path(job_dir(id), "status.json"))
  }
  st$job_id <- id
  st
}

.job_launch <- function(entry) {
  helper_files <- normalizePath(file.path(API_ROOT, "R", "serialize.R"))
  worker_file <- normalizePath(file.path(API_ROOT, "R", "job_worker.R"))
  log_path <- file.path(job_dir(entry$id), "worker.log")

  fn <- if (identical(entry$type, "import")) "worker_run_import" else "worker_run_job"
  args <- if (identical(entry$type, "import")) {
    list(
      job_dir = job_dir(entry$id),
      spec = entry$extra$spec,
      helper_files = c(normalizePath(file.path(API_ROOT, "R", "sources", "source_twitter.R")))
    )
  } else {
    list(
      job_dir = job_dir(entry$id),
      dataset_dir = dataset_dir(entry$dataset_id),
      params = entry$params,
      helper_files = helper_files
    )
  }

  proc <- callr::r_bg(
    func = function(worker_file, fn, args) {
      source(worker_file, local = FALSE)
      do.call(fn, args)
    },
    args = list(worker_file = worker_file, fn = fn, args = args),
    stdout = log_path, stderr = "2>&1",
    env = c(callr::rcmd_safe_env(), MAX_GROUP_SIZE = as.character(cfg_num("MAX_GROUP_SIZE", 20000)))
  )
  entry$process <- proc
  entry$status <- "running"
  entry$started_at <- Sys.time()
  assign(entry$id, entry, envir = .jobs)
}

jobs_tick <- function() {
  entries <- mget(ls(.jobs), envir = .jobs)

  running <- Filter(function(e) !is.null(e$process) && e$process$is_alive(), entries)

  # Kill overruns; job_status() will report them as failed via the log tail.
  for (e in running) {
    if (difftime(Sys.time(), e$started_at, units = "secs") > jobs_timeout_s()) {
      try(e$process$kill(), silent = TRUE)
      write_json_file(
        list(status = "failed", stage = "timeout",
             error = sprintf("job exceeded JOB_TIMEOUT_S (%ds)", jobs_timeout_s())),
        file.path(job_dir(e$id), "status.json")
      )
    }
  }

  n_running <- length(Filter(function(e) e$process$is_alive(), running))
  queued <- Filter(function(e) identical(e$status, "queued"), entries)
  queued <- queued[order(vapply(queued, function(e) as.numeric(e$queued_at), numeric(1)))]
  slots <- jobs_max_concurrent() - n_running
  for (e in utils::head(queued, max(slots, 0))) {
    .job_launch(e)
  }
}

.last_sweep <- new.env(parent = emptyenv())
jobs_schedule_tick <- function() {
  later::later(function() {
    tryCatch(jobs_tick(), error = function(e) message("jobs_tick error: ", conditionMessage(e)))
    last <- mget("t", envir = .last_sweep, ifnotfound = list(t = as.POSIXct(0)))$t
    if (difftime(Sys.time(), last, units = "hours") > 1) {
      assign("t", Sys.time(), envir = .last_sweep)
      tryCatch(sweep_expired(), error = function(e) message("sweep error: ", conditionMessage(e)))
    }
    jobs_schedule_tick()
  }, delay = 2)
}
