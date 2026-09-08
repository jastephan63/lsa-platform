# Performance at load size

What happens when the sample grows 38x — from ~2.4k to ~91k students — and
what the query plans say about it. Numbers are from a MacBook Air (Apple
Silicon, PostgreSQL 16 in a 4 GB Docker VM) using `make data-large`
(scale 42); the on-demand [perf workflow](../.github/workflows/perf.yml)
reproduces the run on a CI runner.

## The load

| | default (`make data`) | load size (`make data-large`) |
| --- | --- | --- |
| schools / students | 118 / 2 352 | 4 543 / 90 819 |
| responses | 63 750 | 2 419 080 |
| replicate-weight rows | 250 750 | 10 563 316 |
| jackknife replicates | 118 | 131 (variance zones cap the growth) |
| CSV on disk | ~9 MB | 377 MB |
| generation time | ~3 s | 2 m 50 s |
| validate + ingest (single transaction) | ~5 s | 9 m 15 s |

Two design decisions earn their keep at this size:

- **Variance zones** (migration 0008): with one replicate per school the
  replicate-weight table would hold 4 543 × 80 636 ≈ 366M rows; grouping
  schools into ≤ ~130 zones keeps it at 10.6M while preserving the
  jackknife's stratum structure.
- **The single-transaction batch load** stays atomic at 13M rows: the old
  data remains queryable until the COPY commits, and a failed load leaves
  nothing behind. The cost is that the ingest is wall-clock-bound by COPY
  and row-level pydantic validation (~9 minutes here); at this volume real
  pipelines move validation into sampled checks plus database constraints.

## Query plans (EXPLAIN ANALYZE at 91k students)

| view | execution time | plan shape |
| ---- | -------------- | ---------- |
| `canton_competency` | ~505 ms | seq scan → hash join → hash aggregate |
| `canton_ses_competency` | ~512 ms | same, one more grouping key |
| `canton_response_rate` | ~32 ms | single seq scan of `student` + window functions |

The planner chooses sequential scans everywhere, and it is right: these
views aggregate the whole table, so no additional index would be used —
the existing primary keys and the `student(school_id)`/`student(canton)`
indexes serve the row-level workloads (ingest FK checks, analyst joins),
not the aggregates. This is the measurement that stops "add an index" from
being a reflex.

## Consequence for the API

Half a second per request is fine for an analyst but wrong for a public
endpoint. At this size the correct move is precomputation, not indexing:
`REFRESH MATERIALIZED VIEW` after each ingest would make every API read a
few milliseconds, at the cost of one refresh step in the load pipeline.
Deliberately not implemented — the default dataset doesn't need it, and
the decision is recorded here with the evidence instead of speculatively
in code.
