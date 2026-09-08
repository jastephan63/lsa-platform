"""The widened public surface: national, uncertainty, proficiency, sex, items."""

import os

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


def test_national_summary_shape(client: TestClient) -> None:
    row = client.get("/api/results/national").json()
    assert row["n_schools"] > 50
    assert row["n_participants"] > 1000
    assert 0.5 < float(row["response_rate"]) <= 1
    assert 300 < float(row["mean_score"]) < 700
    assert row["n_items"] == 30


def test_item_stats_cover_every_item(client: TestClient) -> None:
    rows = client.get("/api/results/items").json()
    assert len(rows) == 30
    for row in rows:
        assert set(row) == {
            "item_id", "domain", "n_responses", "facility", "weighted_facility"
        }
        assert 0 <= float(row["facility"]) <= 1


def test_proficiency_bands_sum_to_100(client: TestClient) -> None:
    rows = client.get("/api/results/proficiency-levels").json()
    assert len(rows) == 26
    for row in rows:
        if row["pct_below"] is None:
            continue
        total = float(row["pct_below"]) + float(row["pct_middle"]) + float(row["pct_above"])
        assert abs(total - 100) < 0.35  # three independently rounded shares


def test_by_sex_has_six_large_cells(client: TestClient) -> None:
    rows = client.get("/api/results/by-sex").json()
    assert len(rows) == 6
    assert {(r["sex"], r["language_region"]) for r in rows} == {
        (s, lr) for s in ("f", "m") for lr in ("de", "fr", "it")
    }


def test_uncertainty_serves_published_inference(client: TestClient) -> None:
    """The statistician's table reaches the API once published — and the
    suppression contract holds there too."""
    from lsa import db

    with db.connect() as conn:
        conn.execute("DELETE FROM analysis_result")
        conn.execute(
            "INSERT INTO analysis_result "
            "(group_type, group_id, n, estimate, se, ci_lower, ci_upper, suppressed) "
            "VALUES ('canton', 'BE', 150, 505.1, 8.2, 489.0, 521.2, false),"
            "       ('canton', 'AI', 4, NULL, NULL, NULL, NULL, true)"
        )
        conn.commit()

    rows = client.get("/api/results/uncertainty").json()
    by_id = {r["group_id"]: r for r in rows}
    assert float(by_id["BE"]["se"]) == 8.2
    assert float(by_id["BE"]["ci_lower"]) < float(by_id["BE"]["estimate"])
    assert by_id["AI"]["estimate"] is None and by_id["AI"]["se"] is None
    assert "computed_at" in by_id["BE"]

    with db.connect() as conn:
        conn.execute("DELETE FROM analysis_result")
        conn.commit()


def test_index_page_shows_all_sections(client: TestClient) -> None:
    body = client.get("/").text
    for fragment in (
        "national mean score",
        "Proficiency bands",
        "Group comparisons",
        "Participation by canton",
        "Item statistics",
        "/api/results/uncertainty",
    ):
        assert fragment in body, f"missing section: {fragment}"
