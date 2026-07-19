#!/usr/bin/env Rscript
# Export the bundled CooRTweet datasets as CSV fixtures for API testing.
# Usage: Rscript api/scripts/export_fixtures.R [out_dir]

suppressMessages(library(CooRTweet))
suppressMessages(library(data.table))

out_dir <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(out_dir)) out_dir <- "api/tests/fixtures"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

data(russian_coord_tweets)
fwrite(russian_coord_tweets, file.path(out_dir, "russian_coord_tweets.csv"))

data(german_elections)
fwrite(german_elections, file.path(out_dir, "german_elections.csv"))

cat(sprintf(
  "wrote %s (%d rows), %s (%d rows)\n",
  file.path(out_dir, "russian_coord_tweets.csv"), nrow(russian_coord_tweets),
  file.path(out_dir, "german_elections.csv"), nrow(german_elections)
))
