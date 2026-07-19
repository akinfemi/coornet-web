# Build from the repo root:
#   docker build -f docker/api.Dockerfile -t coortweet-api .
# r2u = binary CRAN packages via apt (minutes, not hours).
# (Docker Hub mirror of ghcr.io/rocker-org/r2u — ghcr denies anonymous pulls
# from some networks.)
FROM eddelbuettel/r2u:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    r-cran-plumber r-cran-callr r-cran-jsonlite r-cran-uuid r-cran-httr2 \
    r-cran-later r-cran-ps r-cran-readr r-cran-r.utils \
    r-cran-data.table r-cran-tidytable r-cran-rcppsimdjson r-cran-lubridate \
    r-cran-igraph r-cran-stringi \
    && rm -rf /var/lib/apt/lists/*

# The CooRTweet submodule must be checked out (git clone --recurse-submodules).
COPY CooRTweet /src/CooRTweet
RUN test -f /src/CooRTweet/DESCRIPTION || \
    (echo "CooRTweet/DESCRIPTION missing — clone with --recurse-submodules" && exit 1)
RUN R CMD INSTALL /src/CooRTweet

WORKDIR /app
COPY api /app/api

ENV DATA_DIR=/data \
    PORT=8000
VOLUME /data
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD curl -sf http://localhost:8000/api/v1/healthz || exit 1

CMD ["Rscript", "/app/api/entrypoint.R"]
