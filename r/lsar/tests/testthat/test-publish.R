test_that("publish_results writes, suppresses, and replaces", {
  skip_if(Sys.getenv("POSTGRES_HOST") == "", "needs a PostgreSQL instance")
  conn <- lsa_connect()
  on.exit(DBI::dbDisconnect(conn))

  results <- data.frame(
    region = c("de", "fr"),
    n = c(1500, 5),
    estimate = c(502.11, 480.5),
    se = c(4.2, 30.1),
    ci_lower = c(493.9, 421.5),
    ci_upper = c(510.3, 539.5),
    suppressed = c(FALSE, TRUE)
  )
  # Suppressed rows carry no values — mirror what suppress_small_cells does.
  results[results$suppressed,
          c("estimate", "se", "ci_lower", "ci_upper")] <- NA

  expect_equal(
    publish_results(conn, results, "language_region"), 2,
    ignore_attr = TRUE
  )
  back <- DBI::dbGetQuery(conn, "SELECT * FROM analysis_result
                                 WHERE group_type = 'language_region'
                                 ORDER BY group_id")
  expect_equal(nrow(back), 2)
  expect_equal(back$group_id, c("de", "fr"))
  expect_true(is.na(back$estimate[back$suppressed]))
  expect_false(is.na(back$se[!back$suppressed]))

  # Publishing again replaces, never accumulates.
  publish_results(conn, results[1, ], "language_region")
  n_after <- DBI::dbGetQuery(conn, "SELECT count(*) AS n FROM analysis_result
                                    WHERE group_type = 'language_region'")$n
  expect_equal(as.numeric(n_after), 1)
})
