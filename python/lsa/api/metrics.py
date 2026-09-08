"""Prometheus metrics. Labels use the matched route template, never the raw
path, so cardinality stays bounded."""

from fastapi import Request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    Counter,
    Histogram,
    generate_latest,
)

REQUESTS = Counter(
    "lsa_http_requests_total",
    "HTTP requests handled",
    ["method", "route", "status"],
)

DURATION = Histogram(
    "lsa_http_request_duration_seconds",
    "Request duration by route",
    ["route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5),
)


def route_label(request: Request) -> str:
    """The route template (e.g. /api/results/cantons); 'unmatched' for 404s."""
    route = request.scope.get("route")
    return getattr(route, "path", "unmatched")


def record(request: Request, status: int, duration_s: float) -> None:
    route = route_label(request)
    REQUESTS.labels(request.method, route, str(status)).inc()
    DURATION.labels(route).observe(duration_s)


def latest() -> tuple[bytes, str]:
    return generate_latest(), CONTENT_TYPE_LATEST
