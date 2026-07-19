#!/usr/bin/env Rscript
# Run the API unit tests: Rscript api/tests/run_tests.R
suppressMessages({
  library(testthat)
  library(data.table)
})
API_DIR <- normalizePath(file.path(dirname(sub(
  "^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)
)), ".."))
test_dir(file.path(API_DIR, "tests", "testthat"), stop_on_failure = TRUE)
