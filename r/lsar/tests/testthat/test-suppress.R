# Disclosure-control contract: these tests exist so that CI fails if a cell
# below the publication threshold could ever leave the package unsuppressed.

test_that("cells below the threshold are never published", {
  df <- data.frame(
    canton = c("BE", "AI", "UR"),
    n = c(120, 9, 10),
    estimate = c(512.3, 480.1, 495.0),
    imputation_var = c(1.2, 3.4, 2.1)
  )
  out <- suppress_small_cells(df, n_col = "n",
                              value_cols = c("estimate", "imputation_var"))
  # AI (n = 9) is below the default threshold of 10: every value column NA.
  expect_true(all(is.na(out[out$canton == "AI", c("estimate", "imputation_var")])))
  expect_true(out$suppressed[out$canton == "AI"])
  # n = 10 is exactly at the threshold and must be published.
  expect_false(any(is.na(out[out$canton == "UR", c("estimate", "imputation_var")])))
  # The suppressed row is kept, not dropped.
  expect_equal(nrow(out), 3)
})

test_that("the default threshold matches the documented policy of 10", {
  df <- data.frame(n = c(9, 10), estimate = c(1, 2))
  out <- suppress_small_cells(df, n_col = "n", value_cols = "estimate")
  expect_equal(is.na(out$estimate), c(TRUE, FALSE))
})

test_that("suppression refuses silently invalid input", {
  df <- data.frame(n = 5, estimate = 1)
  expect_error(suppress_small_cells(df, n_col = "missing", value_cols = "estimate"))
  expect_error(suppress_small_cells(df, n_col = "n", value_cols = "estimate",
                                    threshold = 0))
})
