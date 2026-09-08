# API service image: multi-stage so build tooling never reaches the runtime
# layer, non-root, digest-pinned base. Built from the repository root:
#   docker build -f docker/api.Dockerfile .
# The digest is refreshed deliberately (see docs/security.md), not on rebuild.

ARG PYTHON_BASE=python:3.12-slim@sha256:78387bc3881b8273120a12ebe6c1ab22b018ccc2c9adf565ae1ac9b536e184ea

FROM ${PYTHON_BASE} AS builder
WORKDIR /build
COPY python/pyproject.toml ./
COPY python/lsa ./lsa
RUN pip install --no-cache-dir --prefix=/install .

FROM ${PYTHON_BASE}
# Never run as root: the service needs no privileges at all. Fixed uid/gid so
# files on shared volumes are readable across this and the analysis image.
RUN groupadd --system --gid 10001 lsa \
    && useradd --system --uid 10001 --gid lsa --no-create-home lsa
COPY --from=builder /install /usr/local
USER lsa
EXPOSE 8000
# The container is healthy when the liveness endpoint answers; stdlib only,
# because curl is deliberately not installed in the runtime image.
HEALTHCHECK --interval=15s --timeout=3s --retries=3 CMD \
  ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/healthz', timeout=2)"]
ENTRYPOINT ["uvicorn", "lsa.api.app:app", "--host", "0.0.0.0", "--port", "8000"]
