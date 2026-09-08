#!/usr/bin/env Rscript
# Batch analysis job: compute weighted competency means with design-based
# uncertainty (jackknife replicate weights + Rubin's rules), apply
# small-cell suppression, publish the results into the analysis_result
# table for the API to serve, and print the canton table to stdout (CSV).
# This is what the analysis/publish containers run, as the analyst role.

library(lsar)

conn <- lsa_connect()
on.exit(DBI::dbDisconnect(conn))

students <- fetch_students(conn)
if (nrow(students) == 0) {
  stop("database holds no participants; run the ingest first", call. = FALSE)
}
reps <- fetch_replicates(conn)
rep_weights <- fetch_replicate_weights(conn)

estimate_for <- function(group) {
  out <- pv_group_means_se(students, reps, rep_weights, group)
  suppress_small_cells(
    out,
    n_col = "n",
    value_cols = c("estimate", "se", "ci_lower", "ci_upper",
                   "sampling_var", "imputation_var")
  )
}

by_canton <- estimate_for("canton")
by_region <- estimate_for("language_region")

publish_results(conn, by_canton, "canton")
publish_results(conn, by_region, "language_region")
message(sprintf("published %d canton and %d language-region rows to analysis_result",
                nrow(by_canton), nrow(by_region)))

for (col in c("estimate", "se", "ci_lower", "ci_upper")) {
  by_canton[[col]] <- round(by_canton[[col]], 2)
}
by_canton$sampling_var <- round(by_canton$sampling_var, 4)
by_canton$imputation_var <- round(by_canton$imputation_var, 4)
write.csv(by_canton, stdout(), row.names = FALSE)
