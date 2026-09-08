# ADR 0003: Aggregate in SQL; estimate variance in R

**Status:** accepted

## Context

Weighted competency means could be computed in R (the statistician's home
turf), in Python (the API's language), or in the database. Computing them
in several places risks the worst outcome: two consumers publishing
different numbers for the same cell.

## Decision

Point estimates and small-cell suppression live in SQL views
([0002_views.sql](../../db/migrations/0002_views.sql)); the R package
implements the same estimator plus what SQL is wrong for — variance
estimation across plausible values — and a test asserts both sides agree
exactly ([test-db.R](../../r/lsar/tests/testthat/test-db.R)).

## Rationale

- **One definition, every consumer.** The API, an analyst with psql, and
  the R package all read the same view. The published number cannot fork.
- **Suppression enforced closest to the data.** A view that already NULLs
  small cells protects even a consumer that forgets the rule; the API's
  role cannot bypass it, because it can only see the views.
- **R where R is right.** Rubin's combining rules, and eventually replicate
  weights and BRR/jackknife, are statistical machinery that belongs in a
  tested package, not in SQL gymnastics.
- The cross-language agreement test is the keystone: it turns "two
  implementations" from a liability into mutual verification.

## Consequences

- The estimator exists twice, deliberately — guarded by CI.
- Changing the suppression threshold means one migration plus one R default
  plus one env var; the tests fail loudly when they drift apart.
