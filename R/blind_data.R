#' Blind a data frame
#'
#' Returns a copy of `data` with the same columns, classes and formats, the same
#' number of rows unless `rows` says otherwise, and fake values throughout.
#' Columns are blinded independently: relationships between them are not kept.
#'
#' This reduces the risk of disclosing the real data. It is not a formal privacy
#' guarantee: the column names, classes, row count and the broad shape of each
#' column stay visible.
#'
#' @param data A data frame, tibble or data.table.
#' @param blind_names Rename the columns to `col_01`, `col_02`... and drop the
#'   variable labels, which often describe sensitive content.
#' @param keep_labels Keep the real factor levels and category values, for when
#'   code has to filter on them. `FALSE` replaces them with `A`, `B`, `C`...
#' @param rows Number of rows to generate. `NULL` keeps the input's row count.
#' @param seed A seed, for a reproducible copy. `NULL` picks one without
#'   disturbing the session's random number stream.
#'
#' @return A data frame of the same class as `data`, with a `blind_summary`
#'   attribute describing what was done.
#'
#' @section What happens to each column:
#' Types are decided by values, not only by storage class: a double holding
#' nothing but 0 and 1 is binary, and a double holding whole numbers with few
#' distinct values is discrete. That is what keeps `table(x)`, `x == 1` and
#' `factor(x)` behaving the same way on both copies.
#'
#' * Continuous numeric: drawn from a smoothed inverse CDF of the real column,
#'   so the shape survives; slightly shifted minimum and maximum, the same
#'   number of decimals, the same sign, the same share of exact zeros.
#' * Discrete numeric, whole numbers with few distinct values, 0/1 included: the
#'   same set of values in similar proportions.
#' * Factor, ordered factor, character with few distinct values,
#'   `haven_labelled`: the same number of levels or categories in similar
#'   proportions, relabelled `A`, `B`, `C`... unless `keep_labels`. Order,
#'   unused levels and `haven` codes kept.
#' * Logical: a similar share of `TRUE`.
#' * `Date`, `POSIXct`: dates in a slightly shifted range, same timezone. Dates
#'   that were text in the file stay text, in the same format.
#' * Identifier, meaning nearly all values distinct or a name like `patient_id`:
#'   new unique values of the same shape; a repeated ID repeats a similar number
#'   of times.
#' * Email, phone, URL: obviously fake values of the same shape, at
#'   `example.com`.
#' * Fixed-shape text, such as postcodes and codes with leading zeros: random
#'   letters, digits and punctuation in the same positions.
#' * Free text: placeholder words of similar length.
#' * Constant or all-`NA`: all-`NA` stays; a constant number stays; constant
#'   text is replaced.
#'
#' Every column keeps its share of missing values, and a text file keeps the way
#' it wrote them. Code that depends on the content of free text, on a particular
#' real value existing, or on a relationship between two columns will not work.
#'
#' @seealso [blind_file()] to do the same to a file.
#' @export
#' @examples
#' fake <- blind_data(mtcars, seed = 1)
#' str(fake)
#' attr(fake, "blind_summary")
blind_data <- function(data, blind_names = FALSE, keep_labels = FALSE,
                       rows = NULL, seed = NULL) {
  db_stop_if_not_data(data)
  blind_names <- db_check_flag(blind_names, "blind_names")
  keep_labels <- db_check_flag(keep_labels, "keep_labels")
  n <- db_check_rows(rows, nrow(data))

  specs <- db_detect_all(data)
  blinded <- db_with_seed(
    seed,
    db_blind_frame(data, specs, n, blind_names, keep_labels)
  )

  leak <- db_check_leaks(data, blinded, specs, keep_labels)
  db_stop_on_leak(leak)

  attr(blinded, "blind_summary") <- db_summary(
    tables = list(data = db_describe_table(blinded, specs, keep_labels)),
    leak = leak,
    rows = n
  )
  blinded
}

# Blind every column of one table. Must be called inside db_with_seed(), so that
# a workbook's sheets share one random stream instead of each restarting it.
db_blind_frame <- function(data, specs, n, blind_names, keep_labels) {
  columns <- lapply(seq_along(data), function(i) {
    db_blind_column(data[[i]], specs[[i]], n, keep_labels, names(data)[[i]])
  })
  names(columns) <- names(data)

  if (blind_names) {
    names(columns) <- db_blinded_names(length(columns))
    columns <- lapply(columns, db_drop_label)
  }
  db_rebuild(data, columns, n)
}

db_blinded_names <- function(k) {
  if (k == 0L) {
    return(character())
  }
  sprintf(paste0("col_%0", max(2L, nchar(k)), "d"), seq_len(k))
}

db_drop_label <- function(x) {
  attr(x, "label") <- NULL
  x
}

# Rebuild a table of the same class as the input. Done by attributes rather than
# data.frame(), which would repair duplicated column names and lose the tibble
# or data.table class.
db_rebuild <- function(data, columns, n) {
  attr(columns, "row.names") <- .set_row_names(n)
  if (inherits(data, "data.table")) {
    return(data.table::setDT(columns)[])
  }
  oldClass(columns) <- oldClass(data)
  columns
}

# Argument checks --------------------------------------------------------

db_stop_if_not_data <- function(data) {
  if (!is.data.frame(data)) {
    stop("`data` must be a data frame.", call. = FALSE)
  }
  invisible(data)
}

db_check_flag <- function(value, name) {
  if (length(value) != 1L || is.na(value) || !is.logical(value)) {
    stop("`", name, "` must be TRUE or FALSE.", call. = FALSE)
  }
  value
}

db_check_rows <- function(rows, available) {
  if (is.null(rows)) {
    return(available)
  }
  bad <- length(rows) != 1L || !is.numeric(rows) || is.na(rows) ||
    rows < 1 || rows != round(rows)
  if (bad) {
    stop("`rows` must be a single whole number of 1 or more, or NULL.",
      call. = FALSE
    )
  }
  as.integer(rows)
}
