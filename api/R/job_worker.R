# Executed inside a callr::r_bg child process — one job per process so a
# crash or OOM can never take down the API. The child re-sources serialize.R
# (passed by path) because closures don't carry sibling functions across
# process boundaries.

# Import job: fetch from an external source (Twitter/X), map to the schema,
# and materialize a normal dataset dir. The bearer token arrives only via the
# in-memory `spec` argument.
worker_run_import <- function(job_dir, spec, helper_files) {
  for (f in helper_files) source(f, local = FALSE)
  suppressPackageStartupMessages(library(data.table))

  status_path <- file.path(job_dir, "status.json")
  set_status <- function(st) {
    tmp <- paste0(status_path, ".tmp")
    jsonlite::write_json(st, tmp, auto_unbox = TRUE, null = "null")
    file.rename(tmp, status_path)
  }

  tryCatch({
    set_status(list(status = "running", stage = "fetching"))
    pages <- fetch_twitter_pages(
      spec,
      max_posts = as.numeric(Sys.getenv("TWITTER_MAX_POSTS", "50000"))
    )
    tweets <- flatten_twitter_pages(pages)
    if (nrow(tweets) == 0) stop("the query returned no tweets")

    set_status(list(status = "running", stage = "mapping"))
    mapped <- map_twitter_intent(tweets, spec$intent)
    if (nrow(mapped) == 0) {
      stop(sprintf("no rows for intent '%s' (e.g. no retweets/URLs in the result set)", spec$intent))
    }

    dir.create(spec$dataset_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(mapped, file.path(spec$dataset_dir, "mapped.rds"))
    meta <- list(
      dataset_id = spec$dataset_id,
      source = "twitter",
      mode = spec$mode,
      intent = spec$intent,
      n_rows = nrow(mapped),
      n_tweets_fetched = nrow(tweets),
      columns = names(mapped),
      created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      mapped = TRUE
    )
    jsonlite::write_json(
      meta, file.path(spec$dataset_dir, "meta.json"),
      auto_unbox = TRUE, null = "null"
    )

    set_status(list(
      status = "succeeded", stage = "done",
      result = list(dataset_id = spec$dataset_id, n_rows = nrow(mapped),
                    n_tweets_fetched = nrow(tweets))
    ))
    invisible(TRUE)
  }, error = function(e) {
    set_status(list(status = "failed", stage = "failed", error = conditionMessage(e)))
    stop(e)
  })
}

worker_run_job <- function(job_dir, dataset_dir, params, helper_files) {
  for (f in helper_files) source(f, local = FALSE)
  suppressPackageStartupMessages({
    library(data.table)
    library(CooRTweet)
  })

  status_path <- file.path(job_dir, "status.json")
  set_stage <- function(stage, status = "running", error = NULL) {
    st <- list(
      status = status, stage = stage,
      updated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    )
    if (!is.null(error)) st$error <- error
    tmp <- paste0(status_path, ".tmp")
    jsonlite::write_json(st, tmp, auto_unbox = TRUE, null = "null")
    file.rename(tmp, status_path)
  }

  tryCatch({
    set_stage("detecting")
    dt <- readRDS(file.path(dataset_dir, "mapped.rds"))

    max_group <- as.numeric(Sys.getenv("MAX_GROUP_SIZE", "20000"))
    sizes <- dt[, .N, by = object_id]
    if (any(sizes$N > max_group)) {
      stop(sprintf(
        "object group too large for pairwise detection: %d rows (max %d). Offending object_id: %s",
        max(sizes$N), max_group, sizes$object_id[which.max(sizes$N)]
      ))
    }

    # Cache detect results per (time_window, min_participation, remove_loops)
    # so edge-weight/subgraph re-runs skip the expensive pairwise step.
    detect_key <- sprintf(
      "detect_%s_%s_%s.rds",
      params$time_window, params$min_participation, tolower(params$remove_loops)
    )
    detect_cache <- file.path(dataset_dir, detect_key)
    if (file.exists(detect_cache)) {
      result <- readRDS(detect_cache)
    } else {
      result <- detect_groups(
        dt,
        time_window = params$time_window,
        min_participation = params$min_participation,
        remove_loops = params$remove_loops
      )
      saveRDS(result, detect_cache)
    }
    if (nrow(result) == 0) {
      stop("no coordinated pairs found with these parameters; try a larger time_window or lower min_participation")
    }

    fast_net <- FALSE
    if (!is.null(params$fast_net)) {
      set_stage("flagging_speed")
      result <- flag_speed_share(
        dt, result,
        min_participation = params$min_participation,
        time_window = params$fast_net$time_window
      )
      fast_net <- TRUE
    }

    set_stage("building_network")
    graph <- generate_coordinated_network(
      result,
      fast_net = fast_net,
      edge_weight = params$edge_weight,
      subgraph = params$subgraph,
      objects = params$objects
    )

    set_stage("stats")
    weight_threshold <- if (fast_net) "fast" else "full"
    accounts <- account_stats(graph, result, weight_threshold = weight_threshold)
    data.table::fwrite(accounts, file.path(job_dir, "accounts.csv"))
    if (isTRUE(params$objects)) {
      groups <- group_stats(graph, weight_threshold = weight_threshold)
      data.table::fwrite(groups, file.path(job_dir, "groups.csv"))
    }
    data.table::fwrite(result, file.path(job_dir, "pairs.csv"))

    set_stage("serializing")
    network_to_json(graph, accounts, params, file.path(job_dir, "network.json"))
    write_graph_exports(graph, job_dir)

    set_stage("done", status = "succeeded")
    invisible(TRUE)
  }, error = function(e) {
    set_stage("failed", status = "failed", error = conditionMessage(e))
    stop(e)
  })
}
