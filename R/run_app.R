# The app is only started here; its interface is in app_ui.R and app_server.R.

# Shiny refuses uploads over 5 MB by default, which is small for a data file.
DB_APP_MAX_UPLOAD <- 1024^3

#' Blind a data file in a browser
#'
#' Opens a small app in the default browser: choose a file, set the options,
#' press *Blind*, read the summary and download the blinded copy. It runs on
#' `127.0.0.1`, so everything stays on this computer, and the uploaded file is
#' deleted when the app closes.
#'
#' This reduces the risk of disclosing the real data. It is not a formal privacy
#' guarantee: the column names, classes, row count and the broad shape of each
#' column stay visible.
#'
#' In RStudio the app can also be started from *Addins* > *Blind a data file*.
#'
#' @return Nothing. Called to run the app, which stops when the browser tab or
#'   the R session is interrupted.
#'
#' @seealso [blind_file()] for the same job at the console.
#' @export
#' @examples
#' if (interactive()) {
#'   run_app()
#' }
run_app <- function() {
  old <- options(shiny.maxRequestSize = DB_APP_MAX_UPLOAD)
  on.exit(options(old), add = TRUE)
  shiny::runApp(db_app(), host = "127.0.0.1", launch.browser = TRUE)
}

# The app object, kept apart from run_app() so that tests can drive the server.
db_app <- function() {
  shiny::shinyApp(ui = db_app_ui(), server = db_app_server)
}
