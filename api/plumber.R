# API assembly (programmatic registration — no plumber annotations).
# Run via entrypoint.R, which sets API_ROOT.

suppressPackageStartupMessages({
  library(plumber)
  library(data.table)
})

if (!exists("API_ROOT")) API_ROOT <- "api"

`%||%` <- function(a, b) if (is.null(a)) b else a

source(file.path(API_ROOT, "R", "storage.R"))
source(file.path(API_ROOT, "R", "validate.R"))
source(file.path(API_ROOT, "R", "jobs.R"))
source(file.path(API_ROOT, "R", "filters.R"))
source(file.path(API_ROOT, "R", "routes_datasets.R"))
source(file.path(API_ROOT, "R", "routes_jobs.R"))

init_storage()

build_api <- function() {
  # Handlers using this serializer set their own Content-Type/Disposition via
  # res$setHeader and return raw bytes.
  raw_serializer <- function() {
    function(val, req, res, errorHandler) {
      tryCatch({
        if (is.raw(val)) res$body <- val
        res$toResponse()
      }, error = function(e) errorHandler(req, res, e))
    }
  }

  pr() |>
    pr_set_serializer(serializer_unboxed_json()) |>
    pr_set_error(handle_error) |>
    pr_filter("log", filter_log) |>
    pr_filter("cors", filter_cors) |>
    pr_filter("body_size", filter_body_size) |>
    pr_get("/api/v1/healthz", function() list(ok = TRUE, time = format(Sys.time(), tz = "UTC"))) |>
    pr_post("/api/v1/datasets", route_upload_dataset,
            parsers = c("multi", "octet")) |>
    pr_post("/api/v1/datasets/<id>/mapping", route_map_dataset) |>
    pr_get("/api/v1/datasets/<id>", route_get_dataset) |>
    pr_post("/api/v1/jobs", route_create_job) |>
    pr_get("/api/v1/jobs/<id>", route_get_job) |>
    pr_get("/api/v1/jobs/<id>/network", route_get_network,
           serializer = raw_serializer()) |>
    pr_get("/api/v1/jobs/<id>/accounts", route_get_accounts) |>
    pr_get("/api/v1/jobs/<id>/groups", route_get_groups) |>
    pr_get("/api/v1/jobs/<id>/export", route_export,
           serializer = raw_serializer())
}
