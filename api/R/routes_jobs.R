# /jobs — create, poll, fetch results, export. Registered in plumber.R.

route_create_job <- function(req, res) {
  body <- req$body
  dataset_id <- body$dataset_id
  if (is.null(dataset_id) || !is_valid_id(dataset_id)) {
    stop(api_error(400, "dataset_id required"))
  }
  meta <- read_json_file(file.path(dataset_dir(dataset_id), "meta.json"))
  if (is.null(meta)) stop(api_error(404, "dataset not found"))
  if (!isTRUE(meta$mapped)) stop(api_error(409, "dataset has no column mapping yet"))

  params <- validate_job_params(if (is.null(body$params)) list() else body$params)
  extra <- list()
  if (!is.null(body$derived_from) && is_valid_id(body$derived_from)) {
    extra$derived_from <- body$derived_from
  }
  id <- job_create(dataset_id, params, type = "analysis", extra = extra)
  res$status <- 202L
  list(job_id = id, status = "queued")
}

route_get_job <- function(req, res, id) {
  if (!is_valid_id(id)) stop(api_error(400, "invalid job id"))
  st <- job_status(id)
  if (is.null(st)) stop(api_error(404, "job not found"))
  record <- read_json_file(file.path(job_dir(id), "params.json"))
  st$type <- record$type
  st$dataset_id <- record$dataset_id
  # An empty R list serializes as [] (array), which clients expecting an
  # object reject — omit params entirely when there are none (import jobs).
  if (length(record$params) > 0) st$params <- record$params
  st$derived_from <- record$derived_from
  st
}

.serve_file <- function(res, path, content_type, download_name = NULL) {
  if (!file.exists(path)) stop(api_error(404, "artifact not available (job not finished?)"))
  res$setHeader("Content-Type", content_type)
  if (!is.null(download_name)) {
    res$setHeader("Content-Disposition", sprintf('attachment; filename="%s"', download_name))
  }
  readBin(path, "raw", file.info(path)$size)
}

route_get_network <- function(req, res, id) {
  if (!is_valid_id(id)) stop(api_error(400, "invalid job id"))
  .serve_file(res, file.path(job_dir(id), "network.json"), "application/json")
}

.paged_csv <- function(path, req) {
  if (!file.exists(path)) stop(api_error(404, "artifact not available (job not finished?)"))
  dt <- data.table::fread(path)
  q <- req$argsQuery
  int_or <- function(x, default) {
    v <- suppressWarnings(as.integer(x %||% default))
    if (is.na(v)) default else v
  }
  page <- max(1, int_or(q$page, 1L))
  per_page <- min(500, max(1, int_or(q$per_page, 50L)))
  if (!is.null(q$sort)) {
    desc <- startsWith(q$sort, "-")
    col <- sub("^-", "", q$sort)
    if (col %in% names(dt)) data.table::setorderv(dt, col, order = if (desc) -1L else 1L)
  }
  n <- nrow(dt)
  from <- (page - 1) * per_page + 1
  rows <- if (from > n) dt[0] else dt[from:min(from + per_page - 1, n)]
  list(total = n, page = page, per_page = per_page, rows = rows)
}

route_get_accounts <- function(req, res, id) {
  if (!is_valid_id(id)) stop(api_error(400, "invalid job id"))
  .paged_csv(file.path(job_dir(id), "accounts.csv"), req)
}

route_get_groups <- function(req, res, id) {
  if (!is_valid_id(id)) stop(api_error(400, "invalid job id"))
  .paged_csv(file.path(job_dir(id), "groups.csv"), req)
}

route_export <- function(req, res, id, format = "graphml") {
  if (!is_valid_id(id)) stop(api_error(400, "invalid job id"))
  jd <- job_dir(id)
  spec <- switch(format,
    graphml = list(file.path(jd, "graph.graphml"), "application/xml", "network.graphml"),
    gexf = list(file.path(jd, "graph.gexf"), "application/xml", "network.gexf"),
    accounts_csv = list(file.path(jd, "accounts.csv"), "text/csv", "accounts.csv"),
    groups_csv = list(file.path(jd, "groups.csv"), "text/csv", "groups.csv"),
    pairs_csv = list(file.path(jd, "pairs.csv"), "text/csv", "pairs.csv"),
    stop(api_error(400, "format must be one of graphml, gexf, accounts_csv, groups_csv, pairs_csv"))
  )
  .serve_file(res, spec[[1]], spec[[2]], spec[[3]])
}
