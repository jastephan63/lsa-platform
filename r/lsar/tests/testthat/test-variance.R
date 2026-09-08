# Hand-computable jackknife case: one stratum, two schools (PSUs), two
# students each, unit weights, one plausible value.
#
#   full estimate      = mean(10, 20, 30, 40)            = 25
#   drop school A      = (2*30 + 2*40) / 4               = 35
#   drop school B      = (2*10 + 2*20) / 4               = 15
#   jk factor          = (2-1)/2                          = 0.5
#   sampling variance  = 0.5 * ((35-25)^2 + (15-25)^2)    = 100  ->  SE = 10

hand_case <- function() {
  data <- data.frame(
    student_id = c("STU00001", "STU00002", "STU00003", "STU00004"),
    region = "X",
    final_weight = 1,
    pv1 = c(10, 20, 30, 40)
  )
  reps <- data.frame(replicate_id = 1:2, jk_factor = 0.5)
  rep_weights <- rbind(
    data.frame(student_id = data$student_id, replicate_id = 1,
               weight = c(0, 0, 2, 2)),   # school A dropped
    data.frame(student_id = data$student_id, replicate_id = 2,
               weight = c(2, 2, 0, 0))    # school B dropped
  )
  list(data = data, reps = reps, rep_weights = rep_weights)
}

test_that("jackknife variance matches the hand computation", {
  h <- hand_case()
  out <- pv_group_means_se(h$data, h$reps, h$rep_weights, "region",
                           pv_cols = "pv1")
  expect_equal(out$estimate, 25)
  expect_equal(out$sampling_var, 100)
  expect_equal(out$imputation_var, 0)
  expect_equal(out$se, 10)
  expect_equal(out$ci_lower, 25 - stats::qnorm(0.975) * 10)
})

test_that("imputation variance follows Rubin when replication adds nothing", {
  h <- hand_case()
  # Replicate weights identical to the full weights: U = 0, so the total
  # variance is exactly (1 + 1/M) * var(per-PV estimates).
  h$rep_weights$weight <- 1
  h$data$pv2 <- h$data$pv1 + 4   # second PV shifts the estimate to 29
  out <- pv_group_means_se(h$data, h$reps, h$rep_weights, "region",
                           pv_cols = c("pv1", "pv2"))
  expect_equal(out$estimate, 27)
  expect_equal(out$sampling_var, 0)
  expect_equal(out$imputation_var, (1 + 1 / 2) * stats::var(c(25, 29)))
})

test_that("full pipeline on the database yields plausible uncertainty", {
  skip_if(Sys.getenv("POSTGRES_HOST") == "", "needs a PostgreSQL instance")
  conn <- lsa_connect()
  on.exit(DBI::dbDisconnect(conn))
  students <- fetch_students(conn)
  skip_if(nrow(students) == 0, "database is empty; run `make ingest` first")
  reps <- fetch_replicates(conn)
  skip_if(nrow(reps) == 0, "no replicate weights loaded")

  out <- pv_group_means_se(students, reps, fetch_replicate_weights(conn),
                           "language_region")
  expect_equal(nrow(out), 3)
  expect_true(all(out$se > 0))
  expect_true(all(out$ci_lower < out$estimate & out$estimate < out$ci_upper))
  # Point estimates must agree with the simpler estimator.
  simple <- pv_group_means(students, "language_region")
  expect_equal(out$estimate, simple$estimate)
})
