# Integration against the platform database. Runs wherever POSTGRES_* is set
# (CI service container, local compose stack); skipped otherwise.

skip_if_no_db <- function() {
  skip_if(Sys.getenv("POSTGRES_HOST") == "", "needs a PostgreSQL instance")
}

test_that("R estimates agree with the SQL view", {
  skip_if_no_db()
  conn <- lsa_connect()
  on.exit(DBI::dbDisconnect(conn))

  students <- fetch_students(conn)
  skip_if(nrow(students) == 0, "database is empty; run `make ingest` first")

  in_r <- pv_group_means(students, "canton")
  in_r <- suppress_small_cells(in_r, n_col = "n", value_cols = "estimate")

  in_sql <- DBI::dbGetQuery(conn, "SELECT canton, n_students, mean_score
                                   FROM canton_competency ORDER BY canton")
  merged <- merge(in_r, in_sql, by = "canton")
  expect_equal(nrow(merged), nrow(in_sql))
  expect_equal(merged$n, merged$n_students)
  # Same estimator, same data: SQL rounds to 2 decimals, so compare there.
  expect_equal(round(merged$estimate, 2), as.numeric(merged$mean_score),
               tolerance = 0.011)
  # Both sides must agree on which cells are suppressed.
  expect_equal(is.na(merged$estimate), is.na(merged$mean_score))
})
