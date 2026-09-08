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
import secrets
import time
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from pathlib import Path
from typing import Any

import psycopg
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.templating import Jinja2Templates
from psycopg import sql

from lsa.api import metrics
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
    metrics.record(request, response.status_code, time.perf_counter() - start)
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


def guard_cells(
    rows: list[dict[str, Any]],
    n_col: str = "n_students",
    value_cols: tuple[str, ...] = ("mean_score",),
) -> list[dict[str, Any]]:
    """Defence in depth: the views suppress small cells; if a value ever
    arrives for a small cell anyway, blank it here and log loudly."""
    for row in rows:
        if row[n_col] < MIN_CELL_SIZE and any(
            row.get(col) is not None for col in value_cols
        ):
            logger.error(
                "suppression guard triggered",
                extra={"extra_fields": {"row_n": row[n_col]}},
            )
            for col in value_cols:
                row[col] = None
    return rows


def require_analyst_token(request: Request) -> None:
    """Bearer-token gate for the restricted tier.

    Deliberately simple (a shared token from the environment, compared in
    constant time) — the demonstrated boundary is that finer aggregates
    require authentication and are audited; a real deployment would put
    OIDC in front. Unset token = the tier is off, not open.
    """
    expected = os.environ.get("LSA_ANALYST_API_TOKEN", "")
    if not expected:
        raise HTTPException(status_code=503, detail="restricted tier is not configured")
    supplied = request.headers.get("authorization", "")
    if not supplied.startswith("Bearer ") or not secrets.compare_digest(
        supplied.removeprefix("Bearer "), expected
    ):
        raise HTTPException(status_code=401, detail="missing or invalid token")


def query_view(request: Request, view: str, order_by: str) -> list[dict[str, Any]]:
    """Read one published view as the API role and write the audit row."""
    allowed = {
        "canton_competency",
        "language_region_competency",
        "canton_response_rate",
        "canton_ses_competency",
        "item_stats",
        "proficiency_levels",
        "sex_competency",
        "national_summary",
        "analysis_result",
    }
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


@app.get("/metrics")
def metrics_endpoint() -> Response:
    """Prometheus scrape target. Operational counters only — no assessment
    data of any granularity leaves through this endpoint."""
    payload, content_type = metrics.latest()
    return Response(content=payload, media_type=content_type)


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


@app.get("/api/results/national")
def national(request: Request) -> dict[str, Any]:
    """One-row national overview: sample sizes, response rate, mean score."""
    rows = query_view(request, "national_summary", "n_schools")
    return rows[0] if rows else {}


@app.get("/api/results/uncertainty")
def uncertainty(request: Request) -> list[dict[str, Any]]:
    """The statistician's table: design-based estimates with standard errors
    and 95% confidence intervals (jackknife + Rubin), published into the
    database by the R analysis job. Empty until that job has run."""
    rows = query_view(request, "analysis_result", "group_id")
    return guard_cells(
        rows, n_col="n", value_cols=("estimate", "se", "ci_lower", "ci_upper")
    )


@app.get("/api/results/proficiency-levels")
def proficiency(request: Request) -> list[dict[str, Any]]:
    """Weighted share of students per proficiency band, by canton."""
    return guard_cells(
        query_view(request, "proficiency_levels", "canton"),
        value_cols=("pct_below", "pct_middle", "pct_above"),
    )


@app.get("/api/results/by-sex")
def by_sex(request: Request) -> list[dict[str, Any]]:
    """Weighted means by sex and language region."""
    return guard_cells(query_view(request, "sex_competency", "language_region"))


@app.get("/api/results/items")
def items(request: Request) -> list[dict[str, Any]]:
    """Classical item analysis: facility per test item (aggregates over
    items, not persons)."""
    return query_view(request, "item_stats", "item_id")


@app.get("/api/restricted/cantons-by-ses")
def canton_ses_results(request: Request) -> list[dict[str, Any]]:
    """Canton x SES-quintile means. Authenticated tier: finer cells, same
    suppression rule — most of these cells are small enough to be withheld."""
    require_analyst_token(request)
    return guard_cells(query_view(request, "canton_ses_competency", "canton"))


def _scale_pct(score: float) -> float:
    """Map a reporting-scale score onto the fixed 400-600 chart window."""
    return round(max(0.0, min(1.0, (score - 400.0) / 200.0)) * 100, 1)


@app.get("/", response_class=HTMLResponse)
def index(request: Request) -> Response:
    """Server-rendered results page: national overview, canton chart with
    confidence-interval whiskers (once the R job has published), proficiency
    bands, group comparisons, response rates, and item statistics."""
    rows = guard_cells(query_view(request, "canton_competency", "canton"))
    national_rows = query_view(request, "national_summary", "n_schools")
    uncertainty_rows = guard_cells(
        query_view(request, "analysis_result", "group_id"),
        n_col="n",
        value_cols=("estimate", "se", "ci_lower", "ci_upper"),
    )
    inference = {
        r["group_id"]: r for r in uncertainty_rows if r["group_type"] == "canton"
    }
    # Geometry is computed here, not in the template: scores map onto a
    # fixed 400-600 reporting-scale window so bars stay comparable across
    # datasets, and the template stays free of arithmetic.
    for row in rows:
        if row["mean_score"] is not None:
            row["bar_pct"] = _scale_pct(float(row["mean_score"]))
        inf = inference.get(row["canton"])
        if inf and inf["se"] is not None:
            row["se"] = inf["se"]
            row["ci_lower"] = inf["ci_lower"]
            row["ci_upper"] = inf["ci_upper"]
            row["ci_lo_pct"] = _scale_pct(float(inf["ci_lower"]))
            row["ci_hi_pct"] = _scale_pct(float(inf["ci_upper"]))
    return templates.TemplateResponse(
        request,
        "index.html",
        {
            "rows": rows,
            "national": national_rows[0] if national_rows else None,
            "has_inference": bool(inference),
            "regions": guard_cells(
                query_view(request, "language_region_competency", "language_region")
            ),
            "levels": guard_cells(
                query_view(request, "proficiency_levels", "canton"),
                value_cols=("pct_below", "pct_middle", "pct_above"),
            ),
            "by_sex": guard_cells(query_view(request, "sex_competency", "language_region")),
            "response_rates": query_view(request, "canton_response_rate", "canton"),
            "items": query_view(request, "item_stats", "item_id"),
            "min_cell_size": MIN_CELL_SIZE,
        },
    )
