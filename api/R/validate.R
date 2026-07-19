# Schema + parameter validation. Mirrors CooRTweet's own contract:
# required columns object_id, account_id, content_id, timestamp_share (UNIX int).

REQUIRED_SCHEMA <- c("object_id", "account_id", "content_id", "timestamp_share")

api_error <- function(status, message, ...) {
  structure(
    class = c("api_error", "error", "condition"),
    list(message = message, status = status, details = list(...))
  )
}

# Coerce timestamps the same way prep_data does (UNIX int or parseable
# datetime, UTC), but return diagnostics instead of stop()ing.
validate_mapped <- function(dt) {
  problems <- list()
  for (col in REQUIRED_SCHEMA) {
    if (!col %in% names(dt)) {
      problems[[length(problems) + 1]] <- sprintf("missing required column '%s'", col)
    }
  }
  if (length(problems) > 0) {
    return(list(ok = FALSE, problems = problems))
  }

  ts <- dt[["timestamp_share"]]
  if (!is.numeric(ts)) {
    parsed <- as.numeric(as.POSIXct(as.character(ts), tz = "UTC"))
    n_bad <- sum(is.na(parsed) & !is.na(ts))
    if (n_bad > 0) {
      bad_rows <- head(which(is.na(parsed) & !is.na(ts)), 5)
      return(list(
        ok = FALSE,
        problems = list(sprintf(
          "timestamp_share: %d values are neither UNIX seconds nor '%%Y-%%m-%%d %%H:%%M:%%S' (e.g. rows %s)",
          n_bad, paste(bad_rows, collapse = ", ")
        ))
      ))
    }
    data.table::set(dt, j = "timestamp_share", value = as.integer(parsed))
  } else {
    data.table::set(dt, j = "timestamp_share", value = as.integer(ts))
  }

  n_na <- sum(!stats::complete.cases(dt[, REQUIRED_SCHEMA, with = FALSE]))
  if (n_na > 0) {
    dt <- dt[stats::complete.cases(dt[, REQUIRED_SCHEMA, with = FALSE])]
  }
  if (nrow(dt) == 0) {
    return(list(ok = FALSE, problems = list("no complete rows after dropping NAs")))
  }

  max_group <- cfg_num("MAX_GROUP_SIZE", 20000)
  group_sizes <- dt[, .N, by = "object_id"]
  oversize <- group_sizes[group_sizes$N > max_group, ]

  list(
    ok = TRUE,
    data = dt,
    report = list(
      n_rows = nrow(dt),
      n_rows_dropped_na = n_na,
      n_accounts = data.table::uniqueN(dt$account_id),
      n_objects = data.table::uniqueN(dt$object_id),
      timestamp_range = as.character(as.POSIXct(
        range(dt$timestamp_share), origin = "1970-01-01", tz = "UTC"
      )),
      oversize_objects = if (nrow(oversize) > 0) {
        list(
          max_group_size = max_group,
          objects = head(oversize$object_id, 10),
          count = nrow(oversize)
        )
      } else NULL
    )
  )
}

validate_job_params <- function(params) {
  defaults <- list(
    time_window = 10,
    min_participation = 2,
    remove_loops = TRUE,
    edge_weight = 0.5,
    subgraph = 0,
    objects = FALSE,
    fast_net = NULL
  )
  p <- utils::modifyList(defaults, params[!vapply(params, is.null, logical(1))])

  ok_num <- function(x, lo, hi) is.numeric(x) && length(x) == 1 && !is.na(x) && x >= lo && x <= hi
  if (!ok_num(p$time_window, 1, 86400 * 7)) stop(api_error(400, "time_window must be 1..604800 seconds"))
  if (!ok_num(p$min_participation, 1, 1e6)) stop(api_error(400, "min_participation must be >= 1"))
  if (!ok_num(p$edge_weight, 0, 1)) stop(api_error(400, "edge_weight must be in [0, 1]"))
  if (!p$subgraph %in% 0:3) stop(api_error(400, "subgraph must be 0, 1, 2, or 3"))
  if (!is.logical(p$remove_loops)) stop(api_error(400, "remove_loops must be boolean"))
  if (!is.logical(p$objects)) stop(api_error(400, "objects must be boolean"))
  if (!is.null(p$fast_net)) {
    if (is.null(p$fast_net$time_window) || !ok_num(p$fast_net$time_window, 1, p$time_window)) {
      stop(api_error(400, "fast_net.time_window must be a number <= time_window"))
    }
    if (p$subgraph %in% 2:3 == FALSE && p$subgraph != 0 && p$subgraph != 1) {
      # subgraph 2/3 only meaningful with fast_net; the reverse is fine
    }
  } else if (p$subgraph %in% 2:3) {
    stop(api_error(400, "subgraph modes 2 and 3 require fast_net"))
  }
  # Drop NULL entries so params serialize cleanly (NULL -> {} in JSON).
  p[!vapply(p, is.null, logical(1))]
}
