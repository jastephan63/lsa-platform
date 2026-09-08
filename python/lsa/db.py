"""Database connection helpers. Configuration comes from the environment only."""

import os

import psycopg


def connection_kwargs() -> dict[str, str]:
    """Read connection parameters from POSTGRES_* environment variables."""
    try:
        return {
            "host": os.environ["POSTGRES_HOST"],
            "port": os.environ["POSTGRES_PORT"],
            "dbname": os.environ["POSTGRES_DB"],
            "user": os.environ["POSTGRES_USER"],
            "password": os.environ["POSTGRES_PASSWORD"],
        }
    except KeyError as exc:
        raise RuntimeError(
            f"missing environment variable {exc.args[0]} (see .env.example)"
        ) from exc


def connect() -> psycopg.Connection:
    """Open a new connection; caller manages transaction scope."""
    return psycopg.connect(psycopg.conninfo.make_conninfo(**connection_kwargs()))
