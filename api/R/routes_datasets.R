# /datasets — upload + column mapping. Plain functions, registered in plumber.R.

route_upload_dataset <- function(req, res) {
  files <- Filter(function(p) is.list(p) && !is.null(p$filename), req$body)
  if (length(files) == 0 && is.raw(req$body)) {
    files <- list(list(filename = "upload.csv", value = req$body))
  }
  if (length(files) == 0) {
    stop(api_error(400, "no file found in request; send multipart/form-data with a CSV part"))
  }
  part <- files[[1]]
  bytes <- part$value
  if (!is.raw(bytes)) stop(api_error(400, "malformed upload"))

  max_mb <- cfg_num("MAX_UPLOAD_MB", 100)
  if (length(bytes) > max_mb * 1024^2) {
    stop(api_error(413, sprintf("upload exceeds MAX_UPLOAD_MB (%d MB)", max_mb)))
  }

  id <- new_id()
  ddir <- dataset_dir(id)
  dir.create(ddir, recursive = TRUE)

  # gzip magic bytes 1f 8b — keep the extension honest so fread dispatches.
  is_gz <- length(bytes) > 2 && bytes[1] == as.raw(0x1f) && bytes[2] == as.raw(0x8b)
  raw_path <- file.path(ddir, if (is_gz) "raw.csv.gz" else "raw.csv")
  writeBin(bytes, raw_path)

  dt <- tryCatch(
    data.table::fread(raw_path, nrows = cfg_num("MAX_ROWS", 2e6) + 1),
    error = function(e) {
      unlink(ddir, recursive = TRUE)
      stop(api_error(400, paste("could not parse CSV:", conditionMessage(e))))
    }
  )
  if (nrow(dt) > cfg_num("MAX_ROWS", 2e6)) {
    unlink(ddir, recursive = TRUE)
    stop(api_error(413, sprintf("dataset exceeds MAX_ROWS (%d)", cfg_num("MAX_ROWS", 2e6))))
  }

  meta <- list(
    dataset_id = id,
    filename = part$filename,
    columns = names(dt),
    n_rows = nrow(dt),
    created_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    mapped = FALSE
  )
  write_json_file(meta, file.path(ddir, "meta.json"))

  list(
    dataset_id = id,
    columns = names(dt),
    n_rows = nrow(dt),
    sample_rows = utils::head(dt, 10)
  )
}

route_map_dataset <- function(req, res, id) {
  if (!is_valid_id(id)) stop(api_error(400, "invalid dataset id"))
  ddir <- dataset_dir(id)
  meta <- read_json_file(file.path(ddir, "meta.json"))
  if (is.null(meta)) stop(api_error(404, "dataset not found"))

  mapping <- req$body[REQUIRED_SCHEMA]
  if (any(vapply(mapping, is.null, logical(1)))) {
    stop(api_error(400, sprintf(
      "mapping must name a source column for each of: %s",
      paste(REQUIRED_SCHEMA, collapse = ", ")
    )))
  }

  raw_path <- if (file.exists(file.path(ddir, "raw.csv.gz"))) {
    file.path(ddir, "raw.csv.gz")
  } else {
    file.path(ddir, "raw.csv")
  }
  dt <- data.table::fread(raw_path)

  missing <- setdiff(unlist(mapping), names(dt))
  if (length(missing) > 0) {
    stop(api_error(400, sprintf("columns not in dataset: %s", paste(missing, collapse = ", "))))
  }
  if (anyDuplicated(unlist(mapping))) {
    stop(api_error(400, "each schema field must map to a distinct column"))
  }

  # Select the mapped source columns first, then rename — a plain
  # prep_data()-style rename would create duplicate column names when the CSV
  # already contains a schema-named column mapped to a different field, and
  # the analysis would silently run on the wrong column.
  dt <- dt[, unlist(mapping[REQUIRED_SCHEMA]), with = FALSE]
  data.table::setnames(dt, REQUIRED_SCHEMA)

  v <- validate_mapped(dt)
  if (!isTRUE(v$ok)) {
    stop(api_error(422, "validation failed", problems = v$problems))
  }

  keep <- v$data[, REQUIRED_SCHEMA, with = FALSE]
  # Character keys keep igraph vertex names stable across R sessions.
  for (col in c("object_id", "account_id", "content_id")) {
    data.table::set(keep, j = col, value = as.character(keep[[col]]))
  }
  saveRDS(keep, file.path(ddir, "mapped.rds"))

  # Invalidate detect caches from any previous mapping.
  unlink(list.files(ddir, pattern = "^detect_.*\\.rds$", full.names = TRUE))

  meta$mapped <- TRUE
  meta$mapping <- mapping
  meta$report <- v$report
  write_json_file(meta, file.path(ddir, "meta.json"))

  list(dataset_id = id, report = v$report)
}

route_get_dataset <- function(req, res, id) {
  if (!is_valid_id(id)) stop(api_error(400, "invalid dataset id"))
  meta <- read_json_file(file.path(dataset_dir(id), "meta.json"))
  if (is.null(meta)) stop(api_error(404, "dataset not found"))
  meta
}
