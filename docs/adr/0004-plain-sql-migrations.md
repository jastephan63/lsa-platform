# ADR 0004: Numbered SQL migrations, not Alembic

**Status:** accepted

## Context

The schema needs versioned, repeatable migrations. Alembic is the standard
Python answer and was the obvious default.

## Decision

Plain numbered `.sql` files applied by a small Bash runner
([migrate.sh](../../scripts/migrate.sh)) that records applied versions and
wraps each file plus its bookkeeping row in one transaction.

## Rationale

- **The schema itself is the demonstrandum.** DDL with comments in files a
  reviewer reads top-to-bottom evidences SQL directly; an ORM-generated
  migration chain evidences knowing Alembic.
- **Language-neutral.** Python, R, psql, and CI all consume the same
  database; tying schema management to one language's tooling puts a Python
  dependency into the R image's and the DBA's workflow. The runner needs
  only bash and psql, so it also runs from the stock postgres image in the
  Kubernetes setup Job.
- **Small enough to audit**: ~80 lines of shell versus a framework — and
  the runner's behaviour (idempotence, transactionality) is itself tested
  in CI.

## Consequences

- No autogeneration from models and no down-migrations; rolling back means
  writing a new forward migration (which is arguably the honest practice
  anyway).
- At team scale, branch conflicts on numbering need a convention; for this
  repository, strictly increasing numbers are enough.
