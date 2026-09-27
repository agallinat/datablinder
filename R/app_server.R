# The Shiny server.
#
# Uploads are copied into a working directory of our own, blinded by
# blind_file(), and that directory is deleted when the session ends, so the real
# data never outlives the app. The browser's own copy of the upload goes as soon
# as we have ours.

db_app_server <- function(input, output, session) {
  work_dir <- db_app_work_dir()
  session$onSessionEnded(function() unlink(work_dir, recursive = TRUE))

  staging <- shiny::reactiveVal(NULL) # our copy of the uploaded file
  result <- shiny::reactiveVal(NULL) # what the last run produced

  shiny::observeEvent(input$blind, {
    info <- input$file
    if (length(info$datapath) == 0L) {
      shiny::showNotification("Choose a data file first.", type = "warning")
      return()
    }
    result(NULL)
    run <- tryCatch(
      shiny::withProgress(
        message = "Blinding",
        detail = "a large file can take a while",
        value = 0.4,
        {
          staged <- db_app_stage(info, work_dir, staging())
          staging(staged)
          db_app_blind(
            staged$path,
            blind_names = isTRUE(input$blind_names),
            keep_labels = isTRUE(input$keep_labels),
            rows = db_app_number(input$rows),
            seed = db_app_number(input$seed)
          )
        }
      ),
      error = function(e) {
        shiny::showNotification(
          conditionMessage(e),
          type = "error", duration = NULL
        )
        NULL
      }
    )
    result(run)
  })

  output$summary <- shiny::renderText({
    run <- result()
    if (is.null(run)) {
      return(DB_APP_PLACEHOLDER)
    }
    db_app_summary_text(run$summary)
  })

  output$sheet <- shiny::renderUI({
    run <- result()
    if (is.null(run) || length(run$tables) < 2L) {
      return(NULL)
    }
    shiny::selectInput("sheet", "Sheet", choices = names(run$tables))
  })

  output$preview <- shiny::renderTable({
    run <- result()
    if (is.null(run)) {
      return(NULL)
    }
    db_app_preview(run$tables, input$sheet)
  })

  output$download <- shiny::renderUI({
    if (is.null(result())) {
      return(NULL)
    }
    shiny::downloadButton(
      "blinded_file", "Download blinded file",
      class = "btn-success"
    )
  })

  output$blinded_file <- shiny::downloadHandler(
    filename = function() result()$name,
    content = function(file) file.copy(result()$path, file, overwrite = TRUE)
  )
}

# One directory per session, under the session's temporary directory.
db_app_work_dir <- function() {
  dir <- tempfile("datablinder-")
  dir.create(dir, recursive = TRUE)
  dir
}

#' Take our own copy of an upload
#'
#' The copy keeps the uploaded file's name, which is what tells `blind_file()`
#' the format, and each upload gets its own directory, so two files with the
#' same name in one session do not collide. A second run of the same upload
#' reuses the copy that is already there.
#'
#' @param info One row of a `fileInput` value.
#' @param dir The session's working directory.
#' @param staged What the previous run staged, or `NULL`.
#' @return A list with the uploaded `datapath` and the `path` of our copy.
#' @noRd
db_app_stage <- function(info, dir, staged = NULL) {
  reusable <- !is.null(staged) &&
    identical(staged$datapath, info$datapath[[1]]) &&
    file.exists(staged$path)
  if (reusable) {
    return(staged)
  }
  target <- file.path(
    tempfile("upload-", tmpdir = dir), basename(info$name[[1]])
  )
  dir.create(dirname(target), recursive = TRUE)
  if (!file.copy(info$datapath[[1]], target, overwrite = TRUE)) {
    stop("The uploaded file could not be read.", call. = FALSE)
  }
  # We have the file now, so the browser's upload is not needed any more.
  unlink(info$datapath[[1]])
  list(datapath = info$datapath[[1]], path = target)
}

db_app_blind <- function(path, blind_names, keep_labels, rows, seed) {
  summary <- blind_file(
    path,
    blind_names = blind_names, keep_labels = keep_labels,
    rows = rows, seed = seed
  )
  list(
    summary = summary,
    path = summary$output,
    name = basename(summary$output),
    # Read back for the preview, so that what is shown can only ever be blinded
    # values.
    tables = db_read(summary$output)$tables
  )
}

# An empty numeric input arrives as NA; blind_file() wants NULL for "no value".
db_app_number <- function(value) {
  if (length(value) != 1L || is.na(value)) {
    return(NULL)
  }
  value
}

# The temporary path of the copy is of no use in the app, and would be noise in
# a summary pasted into a chat.
db_app_summary_text <- function(summary) {
  summary$output <- NULL
  paste(format(summary), collapse = "\n")
}

#' The first rows of one blinded table, as text
#'
#' Everything is shown as text: a preview only has to be readable, and this
#' keeps dates, factors and labelled columns out of the table widget's hands.
#'
#' @param tables The blinded tables, one per sheet.
#' @param sheet The sheet chosen in the app, or `NULL` for the first.
#' @return A data frame of character columns, or `NULL` if there is nothing to
#'   show.
#' @noRd
db_app_preview <- function(tables, sheet = NULL) {
  name <- if (!is.null(sheet) && sheet %in% names(tables)) {
    sheet
  } else {
    names(tables)[[1]]
  }
  table <- utils::head(tables[[name]], DB_APP_PREVIEW_ROWS)
  if (length(table) == 0L) {
    return(NULL)
  }
  shown <- lapply(table, function(column) format(column, trim = TRUE))
  names(shown) <- names(table)
  attr(shown, "row.names") <- .set_row_names(nrow(table))
  class(shown) <- "data.frame"
  shown
}
