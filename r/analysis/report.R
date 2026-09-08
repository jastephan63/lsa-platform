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

results <- pv_group_means(students, "canton")
results <- suppress_small_cells(results, n_col = "n", value_cols = c("estimate", "imputation_var"))
results$estimate <- round(results$estimate, 2)
results$imputation_var <- round(results$imputation_var, 4)

write.csv(results, stdout(), row.names = FALSE)
