# /twitter/import — bring-your-own-key import from the X API v2.
# The bearer token is validated, handed to the worker in memory, and redacted
# from everything that touches disk or logs.

route_twitter_import <- function(req, res) {
  body <- req$body
  spec <- list(
    bearer_token = body$bearer_token,
    mode = body$mode %||% "search_recent",
    query = body$query,
    user_id = body$user_id,
    intent = body$intent %||% "retweets",
    max_results = body$max_results %||% 1000,
    start_time = body$start_time,
    end_time = body$end_time
  )

  if (is.null(spec$bearer_token) || !nzchar(spec$bearer_token)) {
    stop(api_error(400, "bearer_token required (your own X API v2 key; it is never stored)"))
  }
  if (!spec$mode %in% TWITTER_MODES) {
    stop(api_error(400, sprintf("mode must be one of: %s", paste(TWITTER_MODES, collapse = ", "))))
  }
  if (!spec$intent %in% TWITTER_INTENTS) {
    stop(api_error(400, sprintf("intent must be one of: %s", paste(TWITTER_INTENTS, collapse = ", "))))
  }
  if (spec$mode == "user_tweets") {
    if (is.null(spec$user_id) || !grepl("^[0-9]+$", spec$user_id)) {
      stop(api_error(400, "user_tweets mode requires a numeric user_id"))
    }
  } else if (is.null(spec$query) || !nzchar(trimws(spec$query))) {
    stop(api_error(400, "query required for search modes"))
  }
  max_cap <- cfg_num("TWITTER_MAX_POSTS", 50000)
  if (!is.numeric(spec$max_results) || spec$max_results < 10 || spec$max_results > max_cap) {
    stop(api_error(400, sprintf("max_results must be between 10 and %d", max_cap)))
  }

  ds_id <- new_id()
  spec$dataset_id <- ds_id
  spec$dataset_dir <- dataset_dir(ds_id)

  id <- job_create(
    dataset_id = ds_id,
    params = list(),
    type = "import",
    extra = list(spec = spec)
  )
  res$status <- 202L
  list(job_id = id, dataset_id = ds_id, status = "queued")
}
