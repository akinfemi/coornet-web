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
