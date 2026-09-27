# The summary printed after every run.
#
# It describes the blinded data only, never the real data, so that it can be
# pasted into a chat to give an AI the context it needs. That rule is why the
# level labels and code shapes here are read back off the blinded column rather
# than worked out from the real one, and why nothing is shown at all when
# keep_labels kept the real labels.

# How many category labels to list before trailing off.
DB_SUMMARY_LABELS <- 6L

db_summary <- function(tables, leak, output = NULL, rows = NULL) {
  structure(
    list(tables = tables, leak = leak, output = output, rows = rows),
    class = "blind_summary"
  )
}

#' Describe every column of a blinded table
#'
#' @param blinded The blinded table.
#' @param specs Specs from `db_detect_all()` on the real table.
#' @param keep_labels Were real category labels kept?
#' @return A data frame of one row per column.
#' @noRd
db_describe_table <- function(blinded, specs, keep_labels = FALSE) {
  data.frame(
    column = names(blinded),
    class = vapply(blinded, function(x) class(x)[[1L]], character(1),
      USE.NAMES = FALSE
    ),
    note = vapply(
      seq_along(blinded),
      function(i) db_describe(blinded[[i]], specs[[i]], keep_labels),
      character(1)
    ),
    stringsAsFactors = FALSE
  )
}

db_describe <- function(x, spec, keep_labels) {
  switch(spec$type,
    all_na = "all values missing",
    constant = if (is.numeric(x)) {
      "constant, real value kept"
    } else if (keep_labels) {
      "constant, real value kept"
    } else {
      "constant, replaced"
    },
    logical = "logical, similar share of TRUE",
    factor = db_describe_labels(levels(x), keep_labels, "level", "levels"),
    category_text = db_describe_labels(
      sort(unique(db_present(x))), keep_labels, "category", "categories"
    ),
    labelled = db_describe_labels(
      names(attr(x, "labels")), keep_labels, "value label", "value labels"
    ),
    date = "synthetic dates",
    date_text = paste0("synthetic dates, format ", spec$format),
    numeric_discrete = "discrete numbers, same values",
    numeric_continuous = "numeric, synthetic values",
    identifier = paste0("new IDs, same shape (", db_masked_shape(x), ")"),
    email = "fake addresses at example.com",
    url = "fake URLs at example.com",
    phone = paste0("fake numbers, same shape (", db_masked_shape(x), ")"),
    shaped_text = paste0("new codes, same shape (", db_masked_shape(x), ")"),
    free_text = "placeholder words, similar length",
    "blinded"
  )
}

# With keep_labels the labels are real, so they are counted and not named.
db_describe_labels <- function(labels, keep_labels, one, many) {
  word <- if (length(labels) == 1L) one else many
  if (keep_labels) {
    return(paste(length(labels), word, "kept"))
  }
  shown <- labels
  if (length(shown) > DB_SUMMARY_LABELS) {
    shown <- c(shown[seq_len(DB_SUMMARY_LABELS)], "...")
  }
  paste0(length(labels), " ", word, " -> ", paste(shown, collapse = ", "))
}

# The shape of the blinded values, with digits shown as 0: "A-0000000".
db_masked_shape <- function(x) {
  values <- db_present(as.character(x))
  if (length(values) == 0L) {
    return("")
  }
  gsub("9", "0", db_common_shape(values))
}

# Printing --------------------------------------------------------------

#' The summary of a blinded table
#'
#' [blind_file()] returns a `blind_summary` and [blind_data()] hangs one on its
#' result as the `blind_summary` attribute. It describes the blinded data only,
#' never a real value, so it is safe to paste into a chat along with the blinded
#' file, and it tells an AI what each column is before it writes a line of code.
#'
#' Printed, it is the output file if there was one, then one line per column
#' giving the name, the class and what was done, then the row count and the
#' result of the leak check. `format()` returns those same lines as a character
#' vector, for writing them somewhere instead of printing them.
#'
#' Read it before sharing the file. It is the list of decisions the package made,
#' and a column blinded as a category when it is really an identifier, or as free
#' text when it is really a code, is the case to catch.
#'
#' @param x A `blind_summary`, from [blind_file()] or from the `blind_summary`
#'   attribute of a [blind_data()] result.
#' @param ... Ignored.
#'
#' @return `format()` returns a character vector, one element per line.
#'   `print()` prints those lines and returns `x` invisibly.
#'
#' @seealso [blind_file()], [blind_data()].
#' @name blind_summary
#' @examples
#' fake <- blind_data(mtcars[1:3], seed = 1)
#' info <- attr(fake, "blind_summary")
#' info
#' format(info)
NULL

#' @rdname blind_summary
#' @export
format.blind_summary <- function(x, ...) {
  lines <- character()
  if (!is.null(x$output)) {
    lines <- c(lines, paste0("Blinded copy written to ", x$output), "")
  }
  for (name in names(x$tables)) {
    if (length(x$tables) > 1L) {
      lines <- c(lines, paste0("Sheet \"", name, "\":"))
    }
    lines <- c(lines, db_column_lines(x$tables[[name]]))
  }
  if (!is.null(x$rows)) {
    lines <- c(lines, paste0("Rows: ", x$rows))
  }
  lines <- c(lines, paste0(
    "Leak check: ", if (x$leak$passed) "passed" else "failed"
  ))
  matches <- sum(x$leak$matches)
  if (length(x$leak$matches) > 0L && matches > 0L) {
    lines <- c(lines, paste0(
      "Exact numeric or date coincidences: ", matches,
      " (expected with rounded values and shifted date ranges)"
    ))
  }
  lines
}

#' @rdname blind_summary
#' @export
print.blind_summary <- function(x, ...) {
  cat(format(x, ...), sep = "\n")
  invisible(x)
}

# One padded line per column: "age  integer  numeric, synthetic values".
db_column_lines <- function(described) {
  if (nrow(described) == 0L) {
    return("  (no columns)")
  }
  paste0(
    "  ",
    formatC(described$column, width = max(nchar(described$column)), flag = "-"),
    "  ",
    formatC(described$class, width = max(nchar(described$class)), flag = "-"),
    "  ",
    described$note
  )
}
