# Pagination + retry against a local mock server (webfakes via httptest2's
# suggested approach is heavier; a plain httpuv-free mock using httr2's
# req_perform against a local plumber would drag in the full stack, so we
# stub at the boundary: fetch_twitter_pages against a tiny local server).
source(file.path(API_DIR, "R", "sources", "source_twitter.R"))

test_that("fetch_twitter_pages follows next_token and respects the cap", {
  skip_if_not_installed("webfakes")

  page_one <- list(
    data = lapply(1:2, function(i) list(
      id = paste0("a", i), author_id = "u", created_at = "2024-01-01T00:00:00.000Z"
    )),
    meta = list(result_count = 2, next_token = "tok2")
  )
  page_two <- list(
    data = list(list(id = "b1", author_id = "u", created_at = "2024-01-01T00:00:01.000Z")),
    meta = list(result_count = 1)
  )

  app <- webfakes::new_app()
  app$get("/2/tweets/search/recent", function(req, res) {
    if (identical(req$query$next_token, "tok2")) {
      res$send_json(page_two, auto_unbox = TRUE)
    } else {
      res$send_json(page_one, auto_unbox = TRUE)
    }
  })
  srv <- webfakes::local_app_process(app)

  spec <- list(
    bearer_token = "x", mode = "search_recent", query = "test", max_results = 100
  )
  pages <- fetch_twitter_pages(spec, base_url = paste0(srv$url(), "2"))
  expect_equal(length(pages), 2)
  flat <- flatten_twitter_pages(pages)
  expect_equal(flat$tweet_id, c("a1", "a2", "b1"))

  # cap: max_results = 2 stops after the first page
  spec$max_results <- 2
  pages <- fetch_twitter_pages(spec, base_url = paste0(srv$url(), "2"))
  expect_equal(length(pages), 1)
})
