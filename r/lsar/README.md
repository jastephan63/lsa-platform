# lsar

The analysis package of the lsa-platform demonstration project. It does
three things, in the order an analysis runs:

1. **Fetch** — `lsa_connect()` plus `fetch_students()`,
   `fetch_replicates()`, `fetch_replicate_weights()` read the
   pseudonymised microdata from PostgreSQL as the read-mostly analyst role.
2. **Estimate** — `pv_group_means_se()` produces weighted group means with
   design-based standard errors and confidence intervals: jackknife
   replication over variance zones for the sampling part, Rubin's rules
   across the five plausible values for the measurement part. (The simpler
   `pv_group_means()` gives point estimates only and exists to be compared
   against the SQL views.) A hand-computable test pins the estimator down.
3. **Protect and publish** — `suppress_small_cells()` blanks any cell below
   the publication threshold, and `publish_results()` writes the finished
   table into the database's `analysis_result` table, where the API serves
   it.

All statistical terms are explained in
[docs/glossary.md](../../docs/glossary.md); the honest limitations (what
the plausible values simplify, what the replicates do not re-estimate) are
in [docs/data-spec.md](../../docs/data-spec.md). Checked by `R CMD check`
in CI, including a test that requires exact agreement with the SQL views —
same estimates, same suppression decisions.
