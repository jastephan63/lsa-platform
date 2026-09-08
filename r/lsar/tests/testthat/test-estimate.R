test_that("weighted_mean matches a hand computation", {
  # (1*400 + 3*600) / 4 = 550
  expect_equal(weighted_mean(c(400, 600), w = c(1, 3)), 550)
})

test_that("weighted_mean rejects non-positive weights and length mismatch", {
  expect_error(weighted_mean(c(1, 2), w = c(1, 0)))
  expect_error(weighted_mean(c(1, 2), w = 1))
})

test_that("pv_group_means combines plausible values per Rubin", {
  d <- data.frame(
    canton = rep(c("BE", "ZH"), each = 2),
    final_weight = c(1, 1, 2, 2),
    pv1 = c(500, 510, 520, 530),
    pv2 = c(502, 512, 518, 528)
  )
  out <- pv_group_means(d, "canton", pv_cols = c("pv1", "pv2"))
  be <- out[out$canton == "BE", ]
  # Per-PV weighted means for BE: 505 and 507; estimate is their average.
  expect_equal(be$estimate, 506)
  # Between-imputation variance: (1 + 1/2) * var(c(505, 507)) = 1.5 * 2 = 3.
  expect_equal(be$imputation_var, 3)
  expect_equal(be$n, 2)
})

test_that("pv_group_means is invariant to weight rescaling", {
  d <- data.frame(
    g = c("a", "a", "b", "b"),
    final_weight = c(1, 3, 2, 2),
    pv1 = c(400, 600, 500, 520)
  )
  out1 <- pv_group_means(d, "g", pv_cols = "pv1")
  d$final_weight <- d$final_weight * 1000
  out2 <- pv_group_means(d, "g", pv_cols = "pv1")
  expect_equal(out1$estimate, out2$estimate)
})
