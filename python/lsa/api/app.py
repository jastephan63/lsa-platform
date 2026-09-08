"""Aggregate-only results API with a minimal server-rendered page.

Design constraints, enforced structurally:
- Connects as the `lsa_api` role, which can read the published views and
  insert audit rows — never base tables. Row-level data cannot leave this
  service because the database refuses to show it to us in the first place.
- Every data request is written to the audit log (who queried what).
- Small cells arrive already suppressed by the views; a response-side guard
  drops any value that would slip through and logs it as an error.
"""

import logging
import os
import time
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import psycopg
from fastapi import FastAPI, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from psycopg import sql

from lsa.api.logging import configure, request_id_var

logger = logging.getLogger("lsa.api")

MIN_CELL_SIZE = int(os.environ.get("LSA_MIN_CELL_SIZE", "10"))

templates = Jinja2Templates(directory=str(Path(__file__).parent / "templates"))


def api_conninfo() -> str:
    """Connection string for the least-privilege API role."""
    try:
        return psycopg.conninfo.make_conninfo(
            host=os.environ["POSTGRES_HOST"],
            port=os.environ["POSTGRES_PORT"],
            dbname=os.environ["POSTGRES_DB"],
            user=os.environ["LSA_API_DB_USER"],
            password=os.environ["LSA_API_DB_PASSWORD"],
        )
    except KeyError as exc:
        raise RuntimeError(f"missing environment variable {exc.args[0]}") from exc


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    configure(os.environ.get("LSA_LOG_LEVEL", "INFO"))
    logger.info("api starting", extra={"extra_fields": {"min_cell_size": MIN_CELL_SIZE}})
    yield


app = FastAPI(
    title="lsa-platform results API",
    description="Aggregated results of a fictional assessment. Synthetic data only.",
    version="0.1.0",
    lifespan=lifespan,
)


@app.middleware("http")
async def request_context(
    request: Request, call_next: Callable[[Request], Awaitable[Response]]
) -> Response:
    request_id = request.headers.get("x-request-id", str(uuid.uuid4()))
    request_id_var.set(request_id)
    start = time.perf_counter()
    response = await call_next(request)
    response.headers["x-request-id"] = request_id
    logger.info(
        "request",
        extra={
            "extra_fields": {
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": round((time.perf_counter() - start) * 1000, 1),
            }
        },
    )
    return response


def guard_cells(rows: list[dict[str, Any]], n_col: str = "n_students") -> list[dict[str, Any]]:
    """Defence in depth: the views suppress small cells; if a value ever
    arrives for a small cell anyway, blank it here and log loudly."""
    for row in rows:
        if row[n_col] < MIN_CELL_SIZE and row.get("mean_score") is not None:
            logger.error(
                "suppression guard triggered",
                extra={"extra_fields": {"row_n": row[n_col]}},
            )
            row["mean_score"] = None
    return rows


def query_view(request: Request, view: str, order_by: str) -> list[dict[str, Any]]:
    """Read one published view as the API role and write the audit row."""
    allowed = {"canton_competency", "language_region_competency", "canton_response_rate"}
    if view not in allowed:  # pragma: no cover - programming error, not input
        raise ValueError(f"view {view} is not published")
    with psycopg.connect(api_conninfo()) as conn, conn.cursor() as cur:
        cur.execute(
            "INSERT INTO api_audit_log (request_id, client, endpoint, params) "
            "VALUES (%s, %s, %s, %s)",
            (
                request_id_var.get(),
                request.client.host if request.client else "unknown",
                request.url.path,
                str(dict(request.query_params)),
            ),
        )
        cur.execute(
            sql.SQL("SELECT * FROM {} ORDER BY {}").format(
                sql.Identifier(view), sql.Identifier(order_by)
            )
        )
        assert cur.description is not None
        cols = [d.name for d in cur.description]
        return [dict(zip(cols, row, strict=True)) for row in cur.fetchall()]


@app.get("/healthz")
def healthz() -> dict[str, str]:
    """Liveness: the process is up. No dependencies checked."""
    return {"status": "ok"}


@app.get("/readyz")
def readyz() -> Response:
    """Readiness: we can reach the database as the API role."""
    try:
        with psycopg.connect(api_conninfo(), connect_timeout=3) as conn:
            conn.execute("SELECT 1")
    except psycopg.Error as exc:
        logger.warning("readiness check failed", extra={"extra_fields": {"error": str(exc)}})
        return JSONResponse({"status": "unavailable"}, status_code=503)
    return JSONResponse({"status": "ready"})


@app.get("/api/results/cantons")
def canton_results(request: Request) -> list[dict[str, Any]]:
    """Weighted competency means by canton. Aggregates only, small cells suppressed."""
    return guard_cells(query_view(request, "canton_competency", "canton"))


@app.get("/api/results/language-regions")
def language_region_results(request: Request) -> list[dict[str, Any]]:
    """Weighted competency means by language region."""
    return guard_cells(query_view(request, "language_region_competency", "language_region"))


@app.get("/api/results/response-rates")
def response_rates(request: Request) -> list[dict[str, Any]]:
    """Response rates by canton with regional rank and national comparison."""
    return query_view(request, "canton_response_rate", "canton")


@app.get("/", response_class=HTMLResponse)
def index(request: Request) -> Response:
    """Minimal server-rendered results page."""
    rows = guard_cells(query_view(request, "canton_competency", "canton"))
    return templates.TemplateResponse(
        request, "index.html", {"rows": rows, "min_cell_size": MIN_CELL_SIZE}
    )
