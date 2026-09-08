#' Connect to the platform database
#'
#' Connection parameters come from the `POSTGRES_*` environment variables,
#' the same contract every other component uses (see `.env.example`).
#'
#' @return A `DBIConnection`. Caller is responsible for `DBI::dbDisconnect()`.
#' @export
lsa_connect <- function() {
  need <- c("POSTGRES_HOST", "POSTGRES_PORT", "POSTGRES_DB",
            "POSTGRES_USER", "POSTGRES_PASSWORD")
  missing <- need[Sys.getenv(need) == ""]
  if (length(missing) > 0) {
    stop("missing environment variables: ", paste(missing, collapse = ", "),
         " (see .env.example)", call. = FALSE)
  }
  DBI::dbConnect(
    RPostgres::Postgres(),
    host = Sys.getenv("POSTGRES_HOST"),
    port = as.integer(Sys.getenv("POSTGRES_PORT")),
    dbname = Sys.getenv("POSTGRES_DB"),
    user = Sys.getenv("POSTGRES_USER"),
    password = Sys.getenv("POSTGRES_PASSWORD")
  )
}

#' Fetch student-level analysis data
#'
#' Returns one row per participating student with the final weight and the
#' five plausible values, joined in the database rather than in R so the
#' transferred data is exactly what the estimators need.
#'
#' @param conn A `DBIConnection` from [lsa_connect()].
#' @return A data.frame.
#' @export
fetch_students <- function(conn) {
  DBI::dbGetQuery(conn, "
    SELECT s.student_id, s.canton, s.language_region, s.ses_quintile,
           s.final_weight, p.pv1, p.pv2, p.pv3, p.pv4, p.pv5
    FROM student s
    JOIN plausible_value p ON p.student_id = s.student_id
    WHERE s.participated
  ")
}
