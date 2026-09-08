"""Integration test: validate + load the real generated dataset into Postgres.

Requires a running database (POSTGRES_* env vars) with migrations applied —
provided by the service container in CI and by the compose stack locally.
"""

import csv
import os
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

from lsa import db
from lsa.ingest import loader
from lsa.ingest.models import StudentRow

REPO_ROOT = Path(__file__).resolve().parents[2]

pytestmark = pytest.mark.skipif(
    "POSTGRES_HOST" not in os.environ,
    reason="needs a PostgreSQL instance (set POSTGRES_* env vars)",
)


@pytest.fixture(scope="module")
def data_dir(tmp_path_factory: pytest.TempPathFactory) -> Path:
    out = tmp_path_factory.mktemp("raw")
    subprocess.run(
        ["Rscript", str(REPO_ROOT / "r/datagen/generate.R"), "--out", str(out)],
        check=True,
        capture_output=True,
    )
    return out


def load_once(data_dir: Path) -> dict[str, int]:
    result, accepted = loader.validate(data_dir, min_response_rate=0.8)
    assert result.rejects == [], f"clean generated data must not be rejected: {result.rejects[:3]}"
    with db.connect() as conn:
        return loader.load(conn, accepted)


def test_load_is_idempotent_and_views_work(data_dir: Path) -> None:
    first = load_once(data_dir)
    second = load_once(data_dir)
    assert first == second
    assert first["student"] > 1000
    assert first["response"] > 10_000

    with db.connect() as conn, conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM student")
        row = cur.fetchone()
        assert row is not None and row[0] == first["student"]
        # The analytical view must produce a mean for every canton with
        # enough responders, on the familiar reporting scale.
        cur.execute(
            "SELECT count(*), min(mean_score), max(mean_score) "
            "FROM canton_competency WHERE mean_score IS NOT NULL"
        )
        n, lo, hi = cur.fetchone()  # type: ignore[misc]
        assert n >= 20
        assert 300 < float(lo) < float(hi) < 700


def test_broken_row_is_rejected_but_rest_is_accepted(tmp_path: Path, data_dir: Path) -> None:
    broken = tmp_path / "raw"
    shutil.copytree(data_dir, broken)
    with (broken / "students.csv").open(newline="") as fh:
        rows = list(csv.DictReader(fh))
    rows[0]["ses_quintile"] = "9"  # out of the valid 1–5 range
    corrupted_id = rows[0]["student_id"]
    with (broken / "students.csv").open("w", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    result, accepted = loader.validate(broken, min_response_rate=0.8)
    # One row-level reject for the student, and its 30 responses plus one
    # plausible-value row are now orphans — also rejected, keyed by student.
    student_rejects = [f for f in result.rejects if f.source == "students.csv"]
    assert len(student_rejects) == 1
    assert "ses_quintile" in student_rejects[0].message
    assert all(
        f.key.startswith(corrupted_id) or f.source == "students.csv"
        for f in result.rejects
    )
    students = [s for s in accepted["student"] if isinstance(s, StudentRow)]
    assert len(students) == len(rows) - 1
    assert corrupted_id not in {s.student_id for s in students}
    # Dependent records of the rejected student must be cascaded out.
    assert corrupted_id not in {
        r.student_id for r in accepted["response"] if hasattr(r, "student_id")
    }


if __name__ == "__main__":
    sys.exit(pytest.main([__file__]))
