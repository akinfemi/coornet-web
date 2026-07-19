# igraph -> network.json + GraphML/GEXF exports.
# Runs inside the job worker child process.

# The percentile slider in the UI replicates generate_coordinated_network's
# threshold semantics exactly: quantile(type = 7) and STRICT weight > q(p).
# We ship a 101-point grid so the client never has to implement quantiles.
weight_quantile_grid <- function(weights) {
  p <- seq(0, 1, by = 0.01)
  q <- stats::quantile(weights, probs = p, type = 7, names = FALSE)
  list(p = p, q = unname(q))
}

network_to_json <- function(graph, accounts, params, path) {
  vdf <- igraph::as_data_frame(graph, what = "vertices")
  edf <- igraph::as_data_frame(graph, what = "edges")

  weight_col <- if ("weight" %in% names(edf)) "weight" else "weight_full"

  communities <- igraph::cluster_louvain(graph, weights = edf[[weight_col]])
  vdf$community <- as.integer(igraph::membership(communities))
  vdf$degree <- igraph::degree(graph)
  vdf$strength <- igraph::strength(graph, weights = edf[[weight_col]])

  # Join per-account stats so tooltips need a single payload.
  if (!is.null(accounts)) {
    acc <- data.table::as.data.table(accounts)
    vdt <- data.table::as.data.table(vdf)
    stat_cols <- setdiff(names(acc), c("account_id", names(vdt)))
    vdf <- as.data.frame(merge(
      vdt, acc[, c("account_id", stat_cols), with = FALSE],
      by.x = "name", by.y = "account_id", all.x = TRUE
    ))
  }
  names(vdf)[names(vdf) == "name"] <- "id"

  names(edf)[names(edf) == "from"] <- "source"
  names(edf)[names(edf) == "to"] <- "target"

  payload <- list(
    meta = list(
      n_nodes = nrow(vdf),
      n_edges = nrow(edf),
      params = params,
      fast_net = !is.null(params$fast_net),
      weight_quantiles = weight_quantile_grid(edf[[weight_col]]),
      weight_col = weight_col
    ),
    nodes = vdf,
    edges = edf
  )
  jsonlite::write_json(
    payload, path,
    auto_unbox = TRUE, dataframe = "rows", null = "null", na = "null", digits = NA
  )
  invisible(payload)
}

write_graph_exports <- function(graph, dir) {
  igraph::write_graph(graph, file.path(dir, "graph.graphml"), format = "graphml")
  write_gexf(graph, file.path(dir, "graph.gexf"))
}

# Minimal GEXF 1.3 writer (rgexf is archived on CRAN for current R).
# Emits nodes with labels, weighted edges, and float attvalues for the
# numeric edge attributes the pipeline produces.
write_gexf <- function(graph, path) {
  xml_escape <- function(x) {
    x <- gsub("&", "&amp;", x, fixed = TRUE)
    x <- gsub("<", "&lt;", x, fixed = TRUE)
    x <- gsub(">", "&gt;", x, fixed = TRUE)
    gsub('"', "&quot;", x, fixed = TRUE)
  }
  vdf <- igraph::as_data_frame(graph, what = "vertices")
  edf <- igraph::as_data_frame(graph, what = "edges")
  weight_col <- if ("weight" %in% names(edf)) "weight" else "weight_full"

  edge_attr_cols <- names(edf)[vapply(edf, is.numeric, logical(1))]
  edge_attr_cols <- setdiff(edge_attr_cols, weight_col)

  attr_defs <- paste0(
    sprintf('      <attribute id="%d" title="%s" type="double"/>',
            seq_along(edge_attr_cols) - 1, xml_escape(edge_attr_cols)),
    collapse = "\n"
  )

  node_ids <- stats::setNames(seq_len(nrow(vdf)) - 1L, vdf$name)
  nodes_xml <- paste0(
    sprintf('      <node id="%d" label="%s"/>', node_ids, xml_escape(vdf$name)),
    collapse = "\n"
  )

  edge_lines <- vapply(seq_len(nrow(edf)), function(i) {
    attvals <- paste0(
      sprintf('          <attvalue for="%d" value="%s"/>',
              seq_along(edge_attr_cols) - 1,
              vapply(edge_attr_cols, function(cl) format(edf[[cl]][i], digits = 12), character(1))),
      collapse = "\n"
    )
    sprintf(
      '      <edge id="%d" source="%d" target="%d" weight="%s">\n        <attvalues>\n%s\n        </attvalues>\n      </edge>',
      i - 1, node_ids[[edf$from[i]]], node_ids[[edf$to[i]]],
      format(edf[[weight_col]][i], digits = 12), attvals
    )
  }, character(1))

  xml <- paste0(
    '<?xml version="1.0" encoding="UTF-8"?>\n',
    '<gexf xmlns="http://gexf.net/1.3" version="1.3">\n',
    '  <graph defaultedgetype="undirected">\n',
    '    <attributes class="edge">\n', attr_defs, '\n    </attributes>\n',
    '    <nodes>\n', nodes_xml, '\n    </nodes>\n',
    '    <edges>\n', paste0(edge_lines, collapse = "\n"), '\n    </edges>\n',
    '  </graph>\n',
    '</gexf>\n'
  )
  writeLines(xml, path)
}
