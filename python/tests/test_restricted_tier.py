"""The authenticated restricted tier: canton x SES aggregates."""

import os

import pytest
from fastapi.testclient import TestClient

TOKEN = "test-analyst-token"
MIN_CELL_SIZE = 10

pytestmark = pytest.mark.skipif(
    "POSTGRES_HOST" not in os.environ,
    reason="needs a PostgreSQL instance (set POSTGRES_* env vars)",
)


@pytest.fixture
def client(populated_db: None) -> TestClient:
    os.environ["LSA_ANALYST_API_TOKEN"] = TOKEN
    from lsa.api.app import app

    return TestClient(app)


def test_no_token_is_rejected(client: TestClient) -> None:
    assert client.get("/api/restricted/cantons-by-ses").status_code == 401


def test_wrong_token_is_rejected(client: TestClient) -> None:
    response = client.get(
        "/api/restricted/cantons-by-ses",
        headers={"authorization": "Bearer not-the-token"},
    )
    assert response.status_code == 401


def test_unconfigured_tier_is_off_not_open(client: TestClient) -> None:
    saved = os.environ.pop("LSA_ANALYST_API_TOKEN")
    try:
        assert client.get(
            "/api/restricted/cantons-by-ses",
            headers={"authorization": f"Bearer {saved}"},
        ).status_code == 503
    finally:
        os.environ["LSA_ANALYST_API_TOKEN"] = saved


def test_finer_cells_are_served_with_suppression(client: TestClient) -> None:
    rows = client.get(
        "/api/restricted/cantons-by-ses",
        headers={"authorization": f"Bearer {TOKEN}"},
    ).json()
    assert len(rows) == 26 * 5
    for row in rows:
        assert set(row) == {"canton", "ses_quintile", "n_students", "mean_score"}
        if row["n_students"] < MIN_CELL_SIZE:
            assert row["mean_score"] is None, f"published small cell: {row}"
    # The finer breakdown must actually trigger suppression somewhere —
    # otherwise this tier proves nothing.
    assert any(r["mean_score"] is None for r in rows)


def test_restricted_requests_are_audited(client: TestClient) -> None:
    from lsa import db

    client.get(
        "/api/restricted/cantons-by-ses",
        headers={"authorization": f"Bearer {TOKEN}", "x-request-id": "restricted-audit-1"},
    )
    with db.connect() as conn:
        row = conn.execute(
            "SELECT endpoint FROM api_audit_log WHERE request_id = 'restricted-audit-1'"
        ).fetchone()
    assert row is not None and row[0] == "/api/restricted/cantons-by-ses"
