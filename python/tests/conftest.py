"""Shared fixtures for tests that need a populated database."""

import os
import subprocess
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]

API_USER = "lsa_api"
API_PASSWORD = "test-api-password"


@pytest.fixture(scope="session")
def populated_db(tmp_path_factory: pytest.TempPathFactory) -> None:
    """Generate synthetic data, load it, and give the API role a login.

    Mirrors what `make data`, `make ingest`, and `scripts/bootstrap.sh` do for
    a real environment. Session-scoped: one load serves all API tests.
    """
    if "POSTGRES_HOST" not in os.environ:
        pytest.skip("needs a PostgreSQL instance (set POSTGRES_* env vars)")

    from lsa import db
    from lsa.ingest import loader

    out = tmp_path_factory.mktemp("apidata")
    subprocess.run(
        ["Rscript", str(REPO_ROOT / "r/datagen/generate.R"), "--out", str(out)],
        check=True,
        capture_output=True,
    )
    result, accepted = loader.validate(out, min_response_rate=0.8)
    assert not result.rejects
    with db.connect() as conn:
        loader.load(conn, accepted)
        # What scripts/bootstrap.sh does in a real environment: attach
        # credentials to the NOLOGIN role created by migration 0003.
        conn.execute(f"ALTER ROLE {API_USER} WITH LOGIN PASSWORD '{API_PASSWORD}'")

    os.environ["LSA_API_DB_USER"] = API_USER
    os.environ["LSA_API_DB_PASSWORD"] = API_PASSWORD
