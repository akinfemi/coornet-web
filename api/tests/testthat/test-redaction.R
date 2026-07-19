# The bearer token must never reach disk: params.json is written through
# redact_secrets().
source(file.path(API_DIR, "R", "storage.R"))
source(file.path(API_DIR, "R", "jobs.R"))

test_that("job_create redacts credentials in params.json", {
  data_root <- withr::local_tempdir()
  withr::local_envvar(DATA_DIR = data_root)
  init_storage()

  id <- job_create(
    dataset_id = new_id(),
    params = list(),
    type = "import",
    extra = list(spec = list(
      bearer_token = "SUPER-SECRET-TOKEN",
      mode = "search_recent",
      query = "#election",
      nested = list(api_key = "ALSO-SECRET")
    ))
  )

  raw <- readLines(file.path(job_dir(id), "params.json"), warn = FALSE)
  expect_false(any(grepl("SUPER-SECRET-TOKEN", raw, fixed = TRUE)))
  expect_false(any(grepl("ALSO-SECRET", raw, fixed = TRUE)))
  record <- jsonlite::fromJSON(file.path(job_dir(id), "params.json"))
  expect_equal(record$spec$bearer_token, "***")
  expect_equal(record$spec$nested$api_key, "***")
  expect_equal(record$spec$query, "#election")
})
