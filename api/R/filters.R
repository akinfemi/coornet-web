# Plumber filters: CORS (dev), body-size guard, uniform error handling.

filter_cors <- function(req, res) {
  allowed <- cfg("ALLOWED_ORIGINS", "")
  origin <- req$HTTP_ORIGIN
  if (!is.null(origin) && nzchar(allowed)) {
    origins <- trimws(strsplit(allowed, ",")[[1]])
    if (origin %in% origins) {
      res$setHeader("Access-Control-Allow-Origin", origin)
      res$setHeader("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
      res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
    }
  }
  if (identical(req$REQUEST_METHOD, "OPTIONS")) {
    res$status <- 200L
    return(list())
  }
  plumber::forward()
}

filter_body_size <- function(req, res) {
  len <- suppressWarnings(as.numeric(req$CONTENT_LENGTH %||% 0))
  max_mb <- cfg_num("MAX_UPLOAD_MB", 100)
  if (!is.na(len) && len > (max_mb + 10) * 1024^2) {
    res$status <- 413L
    return(list(error = sprintf("request exceeds size limit (%d MB)", max_mb)))
  }
  plumber::forward()
}

# Per-IP hourly quota on the expensive POST endpoints (uploads, jobs, imports).
# This in-app limiter is the enforcement point (stock Caddy has no rate-limit
# module). Keyed on the RIGHT-most X-Forwarded-For hop: the reverse proxy
# appends the real client there, while left-hand entries are client-spoofable.
.rate <- new.env(parent = emptyenv())
filter_rate_limit <- function(req, res) {
  if (!identical(req$REQUEST_METHOD, "POST")) return(plumber::forward())
  limit <- cfg_num("RATE_LIMIT_POSTS_PER_HOUR", 60)
  xff <- req$HTTP_X_FORWARDED_FOR
  ip <- if (!is.null(xff) && nzchar(xff)) {
    utils::tail(trimws(strsplit(xff, ",")[[1]]), 1)
  } else {
    req$REMOTE_ADDR %||% "unknown"
  }
  now <- as.numeric(Sys.time())
  # Evict fully-stale keys so spoofed headers can't grow memory unboundedly.
  if (length(ls(.rate)) > 5000) {
    for (k in ls(.rate)) {
      if (all(get(k, envir = .rate) <= now - 3600)) rm(list = k, envir = .rate)
    }
  }
  hits <- mget(ip, envir = .rate, ifnotfound = list(numeric(0)))[[1]]
  hits <- hits[hits > now - 3600]
  if (length(hits) >= limit) {
    res$status <- 429L
    return(list(error = sprintf(
      "rate limit exceeded (%d requests/hour); try again later", limit
    )))
  }
  assign(ip, c(hits, now), envir = .rate)
  plumber::forward()
}

# Redact anything that looks like a credential before logging /twitter bodies.
filter_log <- function(req, res) {
  path <- req$PATH_INFO %||% ""
  if (!grepl("^/(healthz|api/v1/healthz)", path)) {
    message(sprintf(
      "%s %s %s", format(Sys.time(), "%H:%M:%OS3"), req$REQUEST_METHOD, path
    ))
  }
  plumber::forward()
}

handle_error <- function(req, res, err) {
  if (inherits(err, "api_error")) {
    res$status <- err$status
    body <- list(error = err$message)
    if (length(err$details) > 0) body$details <- err$details
    return(body)
  }
  res$status <- 500L
  message("unhandled error: ", conditionMessage(err))
  list(error = "internal server error")
}
