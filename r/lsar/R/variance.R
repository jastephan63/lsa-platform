#' Weighted group means with full design-based variance
#'
#' Extends [pv_group_means()] with sampling variance from jackknife
#' replicate weights (JKn, delete one PSU) combined with imputation
#' variance across plausible values under Rubin's rules:
#' \deqn{T = \bar{U} + (1 + 1/M) B}
#' where \eqn{\bar{U}} is the mean over plausible values of the replication
#' variance \eqn{U_m = \sum_r f_r (\hat\theta_{mr} - \hat\theta_m)^2}
#' (with \eqn{f_r} the replicate's jackknife factor) and \eqn{B} the
#' between-imputation variance of the per-PV estimates.
#'
#' @param data One row per participating student: the grouping column,
#'   `student_id`, the plausible-value columns, and the full-sample weight.
#' @param reps Replicate definitions: `replicate_id`, `jk_factor`.
#' @param rep_weights Long format: `student_id`, `replicate_id`, `weight`.
#' @param group Name of the grouping column.
#' @param pv_cols Plausible-value column names.
#' @param weight_col Full-sample weight column.
#' @param conf_level Confidence level for the normal-approximation interval.
#' @return A data.frame with `group`, `n`, `estimate`, `se`, `ci_lower`,
#'   `ci_upper`, `sampling_var`, `imputation_var`.
#' @export
pv_group_means_se <- function(data, reps, rep_weights, group,
                              pv_cols = paste0("pv", 1:5),
                              weight_col = "final_weight",
                              conf_level = 0.95) {
  stopifnot(
    is.data.frame(data), "student_id" %in% names(data),
    group %in% names(data), all(pv_cols %in% names(data)),
    all(c("replicate_id", "jk_factor") %in% names(reps)),
    all(c("student_id", "replicate_id", "weight") %in% names(rep_weights))
  )
  m <- length(pv_cols)
  factors <- reps$jk_factor[order(reps$replicate_id)]
  z <- stats::qnorm(1 - (1 - conf_level) / 2)

  groups <- split(data, data[[group]])
  rows <- lapply(names(groups), function(g) {
    d <- groups[[g]]
    # Students x replicates weight matrix for this group only.
    rw <- rep_weights[rep_weights$student_id %in% d$student_id, ]
    w_mat <- matrix(0, nrow = nrow(d), ncol = length(factors),
                    dimnames = list(d$student_id, NULL))
    w_mat[cbind(match(rw$student_id, d$student_id), rw$replicate_id)] <- rw$weight

    per_pv_est <- numeric(m)
    per_pv_uvar <- numeric(m)
    for (i in seq_len(m)) {
      pv <- d[[pv_cols[i]]]
      per_pv_est[i] <- weighted_mean(pv, d[[weight_col]])
      rep_est <- colSums(w_mat * pv) / colSums(w_mat)
      # A replicate that drops this group's only PSU has zero total weight;
      # by convention it contributes nothing to the variance sum.
      rep_est[!is.finite(rep_est)] <- per_pv_est[i]
      per_pv_uvar[i] <- sum(factors * (rep_est - per_pv_est[i])^2)
    }
    estimate <- mean(per_pv_est)
    sampling_var <- mean(per_pv_uvar)
    imputation_var <- if (m > 1) (1 + 1 / m) * stats::var(per_pv_est) else 0
    se <- sqrt(sampling_var + imputation_var)
    data.frame(
      group = g, n = nrow(d), estimate = estimate, se = se,
      ci_lower = estimate - z * se, ci_upper = estimate + z * se,
      sampling_var = sampling_var, imputation_var = imputation_var,
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  names(out)[1] <- group
  out
}

#' Fetch the replicate definitions
#' @param conn A `DBIConnection` from [lsa_connect()].
#' @return A data.frame with `replicate_id`, `canton`, `jk_factor`.
#' @export
fetch_replicates <- function(conn) {
  DBI::dbGetQuery(conn, "SELECT replicate_id, canton, jk_factor
                         FROM replicate ORDER BY replicate_id")
}

#' Fetch the long-format replicate weights
#' @param conn A `DBIConnection` from [lsa_connect()].
#' @return A data.frame with `student_id`, `replicate_id`, `weight`.
#' @export
fetch_replicate_weights <- function(conn) {
  DBI::dbGetQuery(conn, "SELECT student_id, replicate_id, weight
                         FROM replicate_weight")
}
