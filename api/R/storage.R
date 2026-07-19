# Storage layout:
#   $DATA_DIR/datasets/{uuid}/  raw.csv[.gz], mapped.rds, meta.json, detect_*.rds
#   $DATA_DIR/jobs/{uuid}/      params.json, status.json, network.json,
#                               accounts.csv, groups.csv, pairs.csv,
#                               graph.graphml, graph.gexf, worker.log

cfg <- function(name, default = NULL) {
  val <- Sys.getenv(name, unset = NA)
  if (is.na(val) || val == "") return(default)
  val
}

cfg_num <- function(name, default) as.numeric(cfg(name, default))

data_dir <- function() cfg("DATA_DIR", file.path(getwd(), "data-local"))

datasets_root <- function() file.path(data_dir(), "datasets")
jobs_root <- function() file.path(data_dir(), "jobs")

dataset_dir <- function(id) file.path(datasets_root(), id)
job_dir <- function(id) file.path(jobs_root(), id)

init_storage <- function() {
  for (d in c(datasets_root(), jobs_root())) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
}

# IDs are UUIDv4; reject anything else before touching the filesystem so ids
# can never traverse paths.
is_valid_id <- function(id) {
  is.character(id) && length(id) == 1 &&
    grepl("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id)
}

new_id <- function() uuid::UUIDgenerate()

read_json_file <- function(path) {
  if (!file.exists(path)) return(NULL)
  jsonlite::fromJSON(path, simplifyVector = TRUE)
}

write_json_file <- function(x, path) {
  tmp <- paste0(path, ".tmp")
  jsonlite::write_json(x, tmp, auto_unbox = TRUE, null = "null", digits = NA)
  file.rename(tmp, path)
}

# Delete dataset/job dirs whose mtime is older than RETENTION_HOURS.
sweep_expired <- function(retention_hours = cfg_num("RETENTION_HOURS", 72)) {
  cutoff <- Sys.time() - retention_hours * 3600
  removed <- character()
  for (root in c(datasets_root(), jobs_root())) {
    for (d in list.dirs(root, recursive = FALSE)) {
      info <- file.info(d)
      if (!is.na(info$mtime) && info$mtime < cutoff) {
        unlink(d, recursive = TRUE)
        removed <- c(removed, d)
      }
    }
  }
  removed
}
