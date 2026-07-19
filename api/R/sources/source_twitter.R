# Twitter/X API v2 source. Split for testability:
#   fetch_twitter_pages()    — HTTP + pagination + retry (httr2; mock with httptest2)
#   flatten_twitter_pages()  — pure: page JSON -> one tweets data.table
#   map_twitter_intent()     — pure: tweets -> CooRTweet 4-col schema
# The bearer token lives only in the request and the worker's memory —
# never written to disk (params.json is redacted by job_create).

TWITTER_API_BASE <- "https://api.x.com/2"
TWITTER_INTENTS <- c("retweets", "hashtags", "urls", "urls_domains")
TWITTER_MODES <- c("search_recent", "search_all", "user_tweets")

TWEET_FIELDS <- "created_at,author_id,referenced_tweets,entities"
TWEET_EXPANSIONS <- "referenced_tweets.id.author_id"

twitter_endpoint <- function(spec) {
  switch(spec$mode,
    search_recent = list(path = "tweets/search/recent", query_param = "query"),
    search_all = list(path = "tweets/search/all", query_param = "query"),
    user_tweets = list(path = sprintf("users/%s/tweets", spec$user_id), query_param = NULL),
    stop("unknown mode: ", spec$mode)
  )
}

fetch_twitter_pages <- function(
  spec,
  max_posts = 50000,
  base_url = Sys.getenv("TWITTER_API_BASE_URL", TWITTER_API_BASE)
) {
  ep <- twitter_endpoint(spec)
  pages <- list()
  next_token <- NULL
  fetched <- 0

  repeat {
    req <- httr2::request(base_url) |>
      httr2::req_url_path_append(ep$path) |>
      httr2::req_auth_bearer_token(spec$bearer_token) |>
      httr2::req_url_query(
        max_results = min(100, max(10, spec$max_results %||% 100)),
        tweet.fields = TWEET_FIELDS,
        expansions = TWEET_EXPANSIONS
      ) |>
      httr2::req_retry(
        max_tries = 5,
        is_transient = function(resp) httr2::resp_status(resp) %in% c(429, 500, 502, 503),
        after = function(resp) {
          reset <- httr2::resp_header(resp, "x-rate-limit-reset")
          if (!is.null(reset)) max(1, as.numeric(reset) - as.numeric(Sys.time())) else NULL
        }
      )
    if (!is.null(ep$query_param)) {
      req <- httr2::req_url_query(req, !!!stats::setNames(list(spec$query), ep$query_param))
    }
    if (!is.null(spec$start_time)) req <- httr2::req_url_query(req, start_time = spec$start_time)
    if (!is.null(spec$end_time)) req <- httr2::req_url_query(req, end_time = spec$end_time)
    if (!is.null(next_token)) {
      # search endpoints use next_token; the user timeline uses pagination_token
      tok_param <- if (spec$mode == "user_tweets") "pagination_token" else "next_token"
      req <- httr2::req_url_query(req, !!!stats::setNames(list(next_token), tok_param))
    }

    resp <- httr2::req_perform(req)
    page <- httr2::resp_body_json(resp)
    pages[[length(pages) + 1]] <- page

    n <- length(page$data %||% list())
    fetched <- fetched + n
    next_token <- page$meta$next_token
    cap <- min(spec$max_results %||% max_posts, max_posts)
    if (is.null(next_token) || n == 0 || fetched >= cap) break
  }
  pages
}

# pages -> data.table(tweet_id, author_id, created_at, retweeted_id, hashtags, urls)
# hashtags/urls are list-columns; retweeted_id is NA for non-retweets.
flatten_twitter_pages <- function(pages) {
  rows <- list()
  for (page in pages) {
    for (tw in (page$data %||% list())) {
      retweeted <- NA_character_
      for (ref in (tw$referenced_tweets %||% list())) {
        if (identical(ref$type, "retweeted")) retweeted <- ref$id
      }
      tags <- vapply(
        tw$entities$hashtags %||% list(),
        function(h) tolower(h$tag %||% NA_character_), character(1)
      )
      urls <- vapply(
        tw$entities$urls %||% list(),
        function(u) (u$unwound_url %||% u$expanded_url %||% u$url %||% NA_character_),
        character(1)
      )
      rows[[length(rows) + 1]] <- list(
        tweet_id = tw$id,
        author_id = tw$author_id,
        created_at = tw$created_at,
        retweeted_id = retweeted,
        hashtags = list(tags[!is.na(tags)]),
        urls = list(urls[!is.na(urls)])
      )
    }
  }
  if (length(rows) == 0) {
    return(data.table::data.table(
      tweet_id = character(), author_id = character(), created_at = character(),
      retweeted_id = character(), hashtags = list(), urls = list()
    ))
  }
  data.table::rbindlist(rows)
}

url_domain <- function(x) {
  # scheme://[user@]host[:port]/... -> host, minus a leading www.
  host <- stringi::stri_replace_first_regex(x, "^[a-zA-Z][a-zA-Z0-9+.-]*://", "")
  host <- stringi::stri_replace_first_regex(host, "[/?#].*$", "")
  host <- stringi::stri_replace_first_regex(host, "^.*@", "")
  host <- stringi::stri_replace_first_regex(host, ":\\d+$", "")
  tolower(stringi::stri_replace_first_regex(host, "^www\\.", ""))
}

# tweets (from flatten_twitter_pages) -> data.table(object_id, account_id,
# content_id, timestamp_share), mirroring CooRTweet::reshape_tweets semantics.
map_twitter_intent <- function(tweets, intent) {
  ts <- as.integer(as.POSIXct(tweets$created_at, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"))

  if (intent == "retweets") {
    is_rt <- !is.na(tweets$retweeted_id)
    rt <- data.table::data.table(
      object_id = tweets$retweeted_id[is_rt],
      account_id = tweets$author_id[is_rt],
      content_id = tweets$tweet_id[is_rt],
      timestamp_share = ts[is_rt]
    )
    # reshape_tweets.r:91-106 — originals whose tweet_id was retweeted within
    # the collection are appended as shares of their own object_id.
    is_orig <- tweets$tweet_id %in% rt$object_id
    orig <- data.table::data.table(
      object_id = tweets$tweet_id[is_orig],
      account_id = tweets$author_id[is_orig],
      content_id = tweets$tweet_id[is_orig],
      timestamp_share = ts[is_orig]
    )
    out <- rbind(rt, orig)
  } else if (intent == "hashtags") {
    n_each <- vapply(tweets$hashtags, length, integer(1))
    out <- data.table::data.table(
      object_id = unlist(tweets$hashtags, use.names = FALSE),
      account_id = rep(tweets$author_id, n_each),
      content_id = rep(tweets$tweet_id, n_each),
      timestamp_share = rep(ts, n_each)
    )
  } else if (intent %in% c("urls", "urls_domains")) {
    n_each <- vapply(tweets$urls, length, integer(1))
    obj <- unlist(tweets$urls, use.names = FALSE)
    if (intent == "urls_domains") obj <- url_domain(obj)
    out <- data.table::data.table(
      object_id = obj,
      account_id = rep(tweets$author_id, n_each),
      content_id = rep(tweets$tweet_id, n_each),
      timestamp_share = rep(ts, n_each)
    )
  } else {
    stop("unknown intent: ", intent)
  }
  out <- out[!is.na(object_id) & object_id != "" & !is.na(timestamp_share)]
  unique(out)
}

`%||%` <- function(a, b) if (is.null(a)) b else a
