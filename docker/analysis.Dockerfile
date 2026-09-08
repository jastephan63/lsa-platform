# R analysis image: builds and installs the lsar package with its database
# driver, then copies only the installed libraries into a clean runtime stage.
# Built from the repository root:
#   docker build -f docker/analysis.Dockerfile .

ARG R_BASE=rocker/r-ver:4.3.2@sha256:4e32addfc4da3e660f6e0d05ce5e43d3eceb9db58a60b9a142e0dde9a654ead1

FROM ${R_BASE} AS builder
# libpq headers are needed to compile RPostgres, but only at build time.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq-dev && rm -rf /var/lib/apt/lists/*
RUN R -q -e 'install.packages(c("DBI","RPostgres"), repos="https://p3m.dev/cran/__linux__/jammy/latest")'
COPY r/lsar /tmp/lsar
RUN R CMD INSTALL /tmp/lsar

FROM ${R_BASE}
# Runtime needs only the libpq shared library, not the headers or compilers.
RUN apt-get update && apt-get install -y --no-install-recommends \
      libpq5 && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 lsa \
    && useradd --system --uid 10001 --gid lsa --no-create-home lsa \
    # Pre-create the shared data mountpoint so a fresh named volume inherits
    # ownership that the non-root user can write to.
    && mkdir -p /data && chown lsa:lsa /data
COPY --from=builder /usr/local/lib/R/site-library /usr/local/lib/R/site-library
COPY r/analysis/report.R /app/report.R
USER lsa
# A batch job, not a server: liveness means R can load the package stack.
HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD \
  ["Rscript", "-e", "library(lsar)"]
ENTRYPOINT ["Rscript", "/app/report.R"]
