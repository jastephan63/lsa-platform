"""Metrics endpoint and the server-rendered chart."""

import os

import pytest
from fastapi.testclient import TestClient

pytestmark = pytest.mark.skipif(
    "POSTGRES_HOST" not in os.environ,
    reason="needs a PostgreSQL instance (set POSTGRES_* env vars)",
)


@pytest.fixture
def client(populated_db: None) -> TestClient:
    from lsa.api.app import app

    return TestClient(app)


def test_metrics_expose_route_labels_not_raw_paths(client: TestClient) -> None:
    client.get("/api/results/cantons")
    body = client.get("/metrics").text
    assert "lsa_http_requests_total" in body
    assert 'route="/api/results/cantons"' in body
    assert "lsa_http_request_duration_seconds_bucket" in body


def test_metrics_carry_no_assessment_data(client: TestClient) -> None:
    client.get("/api/results/cantons")
    body = client.get("/metrics").text
    # Operational counters only: no canton codes, scores, or identifiers.
    assert "mean_score" not in body
    assert "STU" not in body


def test_index_renders_svg_chart(client: TestClient) -> None:
    body = client.get("/").text
    assert "<svg" in body
    assert "Bar chart of weighted mean scores" in body
    # 26 canton label lines plus bars for published cells.
    assert body.count("<rect") >= 20
