# ADR 0001: PostgreSQL, not DuckDB (or SQLite)

**Status:** accepted

## Context

The platform needs one authoritative store for the assessment data, read by
three consumers (Python ingest, R analysis, aggregate API). An embedded
analytical engine like DuckDB would be simpler to run and famously fast for
exactly this kind of columnar aggregation.

## Decision

PostgreSQL 16.

## Rationale

- **The security model is the application.** The privilege split that this
  system leans on — an API role that *cannot* read microdata, an analyst
  role that cannot write, an audit table the API can only append to — is
  native to a database server with roles and grants. An embedded file
  database has one privilege level: whoever opens the file.
- **Concurrent, network-attached consumers.** Ingest, API replicas, and R
  jobs connect simultaneously from different containers. That is the
  client/server model; with an embedded engine it needs workarounds.
- **Operational surface is part of what this repo demonstrates**: versioned
  migrations, backup/restore with native tools, a StatefulSet, a managed-DB
  trade-off discussion. Real assessment platforms run on server databases.

## Consequences

- More moving parts locally (solved by compose) and a heavier CI setup
  (service containers).
- Analytical queries are fast enough at this scale; at millions of response
  rows, a columnar sidecar (DuckDB reading Postgres, or matviews) would be
  a natural, additive extension rather than a rewrite.
