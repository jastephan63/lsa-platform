#' Suppress small cells before publication
#'
#' Disclosure control: any row whose cell size is below `threshold` has its
#' value columns replaced by `NA`. The row itself is kept, so consumers can
#' see that a cell exists but was not published. The default threshold of 10
#' matches the database views and the API configuration; keeping the three
#' in sync is asserted by tests on each side.
#'
#' @param data A data.frame of aggregated results.
#' @param n_col Name of the column holding the cell size.
#' @param value_cols Character vector of columns to blank for small cells.
#' @param threshold Minimum publishable cell size.
#' @return `data` with small cells suppressed and a logical `suppressed` column.
#' @examples
#' df <- data.frame(canton = c("BE", "AI"), n = c(120, 4), estimate = c(510, 480))
#' suppress_small_cells(df, n_col = "n", value_cols = "estimate")
#' @export
suppress_small_cells <- function(data, n_col, value_cols, threshold = 10) {
  stopifnot(
    is.data.frame(data),
    n_col %in% names(data),
    all(value_cols %in% names(data)),
    is.numeric(threshold), threshold >= 1
  )
  small <- data[[n_col]] < threshold
  for (col in value_cols) {
    data[[col]][small] <- NA
  }
  data$suppressed <- small
  data
}
