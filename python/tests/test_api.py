"""API tests against a populated database (see conftest.populated_db)."""

import os
import uuid

import pytest
from fastapi.testclient import TestClient

MIN_CELL_SIZE = 10

pytestmark = pytest.mark.skipif(
    "POSTGRES_HOST" not in os.environ,
    reason="needs a PostgreSQL instance (set POSTGRES_* env vars)",
)


@pytest.fixture
def client(populated_db: None) -> TestClient:
    from lsa.api.app import app

    return TestClient(app)


def test_healthz_needs_no_database(client: TestClient) -> None:
    assert client.get("/healthz").json() == {"status": "ok"}


def test_readyz_reports_ready(client: TestClient) -> None:
    response = client.get("/readyz")
    assert response.status_code == 200
    assert response.json() == {"status": "ready"}


def test_canton_results_are_aggregates_only(client: TestClient) -> None:
    rows = client.get("/api/results/cantons").json()
    assert len(rows) == 26
    for row in rows:
        # Aggregate columns only — nothing student- or school-shaped.
        assert set(row) == {"canton", "language_region", "n_students", "mean_score"}


def test_no_small_cell_is_ever_published(client: TestClient) -> None:
    """The disclosure-control contract, asserted at the API boundary."""
    for endpoint in ("/api/results/cantons", "/api/results/language-regions"):
        for row in client.get(endpoint).json():
            if row["n_students"] < MIN_CELL_SIZE:
                assert row["mean_score"] is None, f"published small cell: {row}"


def test_request_id_is_echoed_and_generated(client: TestClient) -> None:
    given = str(uuid.uuid4())
    assert client.get("/healthz", headers={"x-request-id": given}).headers[
        "x-request-id"
    ] == given
    generated = client.get("/healthz").headers["x-request-id"]
    assert uuid.UUID(generated)


def test_every_data_request_is_audited(client: TestClient) -> None:
    from lsa import db

    with db.connect() as conn:
        before = conn.execute("SELECT count(*) FROM api_audit_log").fetchone()
    request_id = str(uuid.uuid4())
    client.get("/api/results/cantons", headers={"x-request-id": request_id})
    with db.connect() as conn:
        after = conn.execute("SELECT count(*) FROM api_audit_log").fetchone()
        audited = conn.execute(
            "SELECT endpoint FROM api_audit_log WHERE request_id = %s", (request_id,)
        ).fetchone()
    assert before is not None and after is not None and audited is not None
    assert after[0] == before[0] + 1
    assert audited[0] == "/api/results/cantons"


def test_html_page_renders_table_and_disclaimer(client: TestClient) -> None:
    response = client.get("/")
    assert response.status_code == 200
    assert "synthetic data" in response.text
    assert "<table>" in response.text
    assert "ZH" in response.text


def test_api_role_cannot_read_base_tables(client: TestClient) -> None:
    """Least privilege, proven from the API's own credentials."""
    import psycopg

    from lsa.api.app import api_conninfo

    with (
        psycopg.connect(api_conninfo()) as conn,
        pytest.raises(psycopg.errors.InsufficientPrivilege),
    ):
        conn.execute("SELECT * FROM student LIMIT 1")
