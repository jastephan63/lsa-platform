#!/usr/bin/env Rscript
# Batch analysis job: compute weighted competency means by canton with the
# lsar package, apply small-cell suppression, and write the publishable table
# to stdout (CSV). This is what the analysis container runs.

library(lsar)

conn <- lsa_connect()
on.exit(DBI::dbDisconnect(conn))

students <- fetch_students(conn)
if (nrow(students) == 0) {
  stop("database holds no participants; run the ingest first", call. = FALSE)
}

results <- pv_group_means_se(
  students,
  reps = fetch_replicates(conn),
  rep_weights = fetch_replicate_weights(conn),
  group = "canton"
)
results <- suppress_small_cells(
  results,
  n_col = "n",
  value_cols = c("estimate", "se", "ci_lower", "ci_upper",
                 "sampling_var", "imputation_var")
)
for (col in c("estimate", "se", "ci_lower", "ci_upper")) {
  results[[col]] <- round(results[[col]], 2)
}
results$sampling_var <- round(results$sampling_var, 4)
results$imputation_var <- round(results$imputation_var, 4)

write.csv(results, stdout(), row.names = FALSE)
