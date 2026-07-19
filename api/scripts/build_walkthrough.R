#!/usr/bin/env Rscript
# Precompute walkthrough artifacts from the bundled CooRTweet datasets
# (vignette parameters) into static JSON the frontend serves directly.
# Usage: Rscript api/scripts/build_walkthrough.R [out_dir]   (repo root)

suppressMessages({
  library(CooRTweet)
  library(data.table)
  library(igraph)
})

args <- commandArgs(trailingOnly = TRUE)
out_dir <- if (length(args) >= 1) args[1] else "web/public/walkthrough"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

script_path <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
api_root <- normalizePath(file.path(dirname(script_path), ".."))
source(file.path(api_root, "R", "serialize.R"))

save_network <- function(graph, result, params, path) {
  weight_threshold <- if (isTRUE(params$fast_net_flag)) "fast" else "full"
  accounts <- account_stats(graph, result, weight_threshold = weight_threshold)
  network_to_json(graph, accounts, params, path)
  invisible(NULL)
}

index <- list()

## ---- Russian retweet coordination (vignette.Rmd params) ----
data(russian_coord_tweets)
ru <- as.data.table(russian_coord_tweets)
for (col in c("object_id", "account_id", "content_id")) {
  set(ru, j = col, value = as.character(ru[[col]]))
}

ru_result <- detect_groups(ru, time_window = 60, min_participation = 2)
ru_full <- generate_coordinated_network(ru_result, edge_weight = 0.5, subgraph = 0)
ru_core <- generate_coordinated_network(ru_result, edge_weight = 0.5, subgraph = 1)

save_network(ru_full, ru_result, list(time_window = 60, min_participation = 2,
  edge_weight = 0.5, subgraph = 0), file.path(out_dir, "russian-full.json"))
save_network(ru_core, ru_result, list(time_window = 60, min_participation = 2,
  edge_weight = 0.5, subgraph = 1), file.path(out_dir, "russian-core.json"))

index$russian <- list(
  slug = "russian",
  title = "Pro-government retweet coordination on Russian Twitter",
  dataset = sprintf("%s shares · %s accounts (anonymized; Kulichkina et al. 2024)",
    format(nrow(ru), big.mark = ","), format(uniqueN(ru$account_id), big.mark = ",")),
  stats = list(
    n_rows = nrow(ru),
    n_accounts = uniqueN(ru$account_id),
    n_pairs = nrow(ru_result),
    full_nodes = vcount(ru_full), full_edges = ecount(ru_full),
    core_nodes = vcount(ru_core), core_edges = ecount(ru_core)
  )
)

## ---- German elections: multi-intent + fast network (reproduce_examples.Rmd) ----
data(german_elections)
de <- as.data.table(german_elections)
setnames(de, "timestamp", "timestamp_share")

intents <- c(url = "url_id", domain = "domain_id", hashtag = "hashtag_id", image = "phash_id")
de_results <- list()
for (nm in names(intents)) {
  col <- intents[[nm]]
  d <- de[!is.na(get(col)), .(
    object_id = paste0(nm, "_", get(col)),
    account_id = as.character(account_id),
    content_id = paste0(nm, "_", as.character(post_id)),
    timestamp_share = as.integer(timestamp_share)
  )]
  de_results[[nm]] <- detect_groups(d, time_window = 30, min_participation = 2)
}
de_combined <- rbindlist(de_results)
de_net <- generate_coordinated_network(de_combined, edge_weight = 0.5, subgraph = 1)
save_network(de_net, de_combined, list(time_window = 30, min_participation = 2,
  edge_weight = 0.5, subgraph = 1, intents = names(intents)),
  file.path(out_dir, "german-combined.json"))

# Fast network: URL shares, 60s window, re-flagged at 10s.
de_urls <- de[!is.na(url_id), .(
  object_id = as.character(url_id),
  account_id = as.character(account_id),
  content_id = as.character(post_id),
  timestamp_share = as.integer(timestamp_share)
)]
de_url_result <- detect_groups(de_urls, time_window = 60, min_participation = 2)
de_url_flagged <- flag_speed_share(de_urls, de_url_result,
  min_participation = 2, time_window = 10)
de_fast <- generate_coordinated_network(de_url_flagged, fast_net = TRUE,
  edge_weight = 0.5, subgraph = 2)
save_network(de_fast, de_url_flagged, list(time_window = 60, min_participation = 2,
  edge_weight = 0.5, subgraph = 2, fast_net = list(time_window = 10), fast_net_flag = TRUE),
  file.path(out_dir, "german-fast.json"))

index$german <- list(
  slug = "german",
  title = "Multi-platform coordination in the 2021 German federal election",
  dataset = sprintf("%s posts, Facebook + Twitter (anonymized; Righetti et al. 2022)",
    format(nrow(de), big.mark = ",")),
  stats = list(
    n_rows = nrow(de),
    n_pairs_combined = nrow(de_combined),
    combined_nodes = vcount(de_net), combined_edges = ecount(de_net),
    fast_nodes = vcount(de_fast), fast_edges = ecount(de_fast)
  )
)

jsonlite::write_json(index, file.path(out_dir, "index.json"), auto_unbox = TRUE)

for (f in list.files(out_dir, full.names = TRUE)) {
  cat(sprintf("%-28s %8.1f KB\n", basename(f), file.info(f)$size / 1024))
}
