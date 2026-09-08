#' Publish inference results to the platform's results store
#'
#' Writes the output of [pv_group_means_se()] (after
#' [suppress_small_cells()]) into the `analysis_result` table, replacing any
#' previous publication for the same `group_type`. This is how standard
#' errors and confidence intervals reach the API: R computes them, the
#' database stores them, the API serves them — the jackknife is never
#' re-implemented outside this package.
#'
#' @param conn A `DBIConnection` from [lsa_connect()] — must be the analyst
#'   role, the only one granted write access to `analysis_result`.
#' @param results A data.frame from [pv_group_means_se()] +
#'   [suppress_small_cells()]: the grouping column first, then `n`,
#'   `estimate`, `se`, `ci_lower`, `ci_upper`, `suppressed`.
#' @param group_type Either `"canton"` or `"language_region"`.
#' @return Invisibly, the number of rows published.
#' @export
publish_results <- function(conn, results, group_type) {
  stopifnot(
    group_type %in% c("canton", "language_region"),
    all(c("n", "estimate", "se", "ci_lower", "ci_upper", "suppressed")
        %in% names(results))
  )
  rows <- data.frame(
    group_type = group_type,
    group_id = results[[1]],
    n = results$n,
    estimate = round(results$estimate, 2),
    se = round(results$se, 2),
    ci_lower = round(results$ci_lower, 2),
    ci_upper = round(results$ci_upper, 2),
    suppressed = results$suppressed,
    stringsAsFactors = FALSE
  )
  DBI::dbWithTransaction(conn, {
    DBI::dbExecute(conn, "DELETE FROM analysis_result WHERE group_type = $1",
                   params = list(group_type))
    DBI::dbAppendTable(conn, "analysis_result", rows)
  })
  invisible(nrow(rows))
}
