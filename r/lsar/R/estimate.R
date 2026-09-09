#' Design-weighted mean
#'
#' The elementary estimator behind everything else: a weighted mean using the
#' nonresponse-adjusted design weights.
#'
#' @param x Numeric vector of values.
#' @param w Numeric vector of positive weights, same length as `x`.
#' @return The weighted mean as a single numeric value.
#' @examples
#' weighted_mean(c(400, 600), w = c(1, 3))
#' @export
weighted_mean <- function(x, w) {
  stopifnot(length(x) == length(w), all(is.finite(x)), all(is.finite(w)), all(w > 0))
  sum(w * x) / sum(w)
}

#' Weighted group means over plausible values (point estimates only)
#'
#' Computes the weighted mean per group for each plausible value separately,
#' then combines: the point estimate is the average of the per-PV estimates,
#' and the reported variance is only the between-imputation part under
#' Rubin's rules. For full design-based uncertainty (standard errors and
#' confidence intervals via jackknife replicate weights) use
#' [pv_group_means_se()]; this simpler function remains because the SQL
#' views implement the same point estimator and a test compares the two.
#'
#' @param data A data.frame with one row per student.
#' @param group Name of the grouping column (e.g. `"canton"`).
#' @param pv_cols Character vector of plausible-value column names.
#' @param weight_col Name of the weight column.
#' @return A data.frame with columns `group`, `n`, `estimate`, `imputation_var`.
#' @export
pv_group_means <- function(data, group, pv_cols = paste0("pv", 1:5),
                           weight_col = "final_weight") {
  stopifnot(
    is.data.frame(data),
    group %in% names(data),
    all(pv_cols %in% names(data)),
    weight_col %in% names(data)
  )
  groups <- split(data, data[[group]])
  rows <- lapply(names(groups), function(g) {
    d <- groups[[g]]
    per_pv <- vapply(
      pv_cols,
      function(col) weighted_mean(d[[col]], d[[weight_col]]),
      numeric(1)
    )
    m <- length(per_pv)
    data.frame(
      group = g,
      n = nrow(d),
      estimate = mean(per_pv),
      # Between-imputation variance, inflated by (1 + 1/m) per Rubin.
      imputation_var = (1 + 1 / m) * stats::var(per_pv),
      stringsAsFactors = FALSE
    )
  })
  out <- do.call(rbind, rows)
  names(out)[1] <- group
  out
}
