# Pure-function tests for the Twitter intent mappers — no HTTP involved.
source(file.path(API_DIR, "R", "sources", "source_twitter.R"))

canned_page <- function() {
  list(
    data = list(
      list(
        id = "t1", author_id = "alice", created_at = "2024-01-01T10:00:00.000Z",
        entities = list(
          hashtags = list(list(tag = "Election"), list(tag = "vote")),
          urls = list(list(expanded_url = "https://www.example.com/a?utm=1",
                           unwound_url = "https://news.example.com/story-1"))
        )
      ),
      list(
        id = "t2", author_id = "bob", created_at = "2024-01-01T10:00:05.000Z",
        referenced_tweets = list(list(type = "retweeted", id = "t1")),
        entities = list(urls = list(list(expanded_url = "https://t.co/xyz")))
      ),
      list(
        id = "t3", author_id = "carol", created_at = "2024-01-01T10:00:09.000Z",
        referenced_tweets = list(list(type = "retweeted", id = "t1"))
      ),
      list(
        id = "t4", author_id = "dan", created_at = "2024-01-01T11:00:00.000Z",
        referenced_tweets = list(list(type = "quoted", id = "t9"))
      )
    ),
    meta = list(result_count = 4)
  )
}

test_that("flatten extracts retweets, hashtags, urls", {
  flat <- flatten_twitter_pages(list(canned_page()))
  expect_equal(nrow(flat), 4)
  expect_equal(flat$retweeted_id, c(NA, "t1", "t1", NA))
  expect_equal(flat$hashtags[[1]], c("election", "vote"))
  expect_equal(flat$urls[[1]], "https://news.example.com/story-1")
})

test_that("retweets intent mirrors reshape_tweets originals rule", {
  flat <- flatten_twitter_pages(list(canned_page()))
  out <- map_twitter_intent(flat, "retweets")
  # two retweets of t1, plus t1 itself appended as a share of its own id
  # (it was retweeted within the collection); t4 is a quote, excluded
  expect_equal(nrow(out), 3)
  expect_setequal(out$account_id, c("alice", "bob", "carol"))
  expect_true(all(out$object_id == "t1"))
  orig <- out[out$account_id == "alice"]
  expect_equal(orig$content_id, "t1")
  # timestamps are UTC UNIX seconds
  expect_equal(
    out[out$account_id == "bob"]$timestamp_share,
    as.integer(as.POSIXct("2024-01-01 10:00:05", tz = "UTC"))
  )
})

test_that("hashtags intent lowercases and explodes", {
  flat <- flatten_twitter_pages(list(canned_page()))
  out <- map_twitter_intent(flat, "hashtags")
  expect_equal(nrow(out), 2)
  expect_setequal(out$object_id, c("election", "vote"))
})

test_that("urls intent prefers unwound_url; domains are extracted", {
  flat <- flatten_twitter_pages(list(canned_page()))
  urls <- map_twitter_intent(flat, "urls")
  expect_true("https://news.example.com/story-1" %in% urls$object_id)
  domains <- map_twitter_intent(flat, "urls_domains")
  expect_setequal(domains$object_id, c("news.example.com", "t.co"))
})

test_that("url_domain handles ports, auth, www, and bare hosts", {
  expect_equal(url_domain("https://www.Example.com:8080/p?q=1"), "example.com")
  expect_equal(url_domain("http://user@site.org/x"), "site.org")
  expect_equal(url_domain("https://sub.domain.co.uk/path#frag"), "sub.domain.co.uk")
})

test_that("empty pages produce an empty flat table without error", {
  flat <- flatten_twitter_pages(list(list(meta = list(result_count = 0))))
  expect_equal(nrow(flat), 0)
  expect_equal(nrow(map_twitter_intent(flat, "retweets")), 0)
})
