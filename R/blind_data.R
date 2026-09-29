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
#' @param keep_real Names of columns to copy across **unchanged, with their real
#'   values**, for columns that carry no sensitive information and that code has
#'   to use as they are, such as a treatment arm or a study visit. These columns
#'   keep their real names even under `blind_names`, and are named in the summary
#'   and excluded from the leak check. Cannot be combined with `rows`. Use it
#'   sparingly: see the warning below.
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
#' @section Columns kept real:
#' `keep_real` names columns that are copied over untouched, so their real values
#' end up in the shared copy. It exists because code often has to use a real
#' value to be useful at all, as in `arm == "placebo"`, and hand-editing the
#' blinded file back is worse than asking for it.
#'
#' It is also the one way to make this package disclose real data, so the
#' decision is yours and it is worth making slowly:
#'
#' * A column that is harmless by itself can still identify someone in
#'   combination with the others. A real date of birth, postcode or site, next to
#'   a real sex and a real visit date, can be enough, even with every name
#'   blinded.
#' * The rows still line up. A kept column stays matched to the rest of its row,
#'   which is why `rows` cannot be used at the same time.
#' * The summary says which columns were kept, and the leak check cannot vouch
#'   for them. Read both before sharing the file.
#'
#' The safe default is not to use it. If a column is only needed for its
#' categories and not its contents, `keep_labels` is usually enough.
#'
#' @seealso [blind_file()] to do the same to a file.
#' @export
#' @examples
#' fake <- blind_data(mtcars, seed = 1)
#' str(fake)
#' attr(fake, "blind_summary")
#'
#' # cyl copied over with its real values, everything else blinded
#' arms <- blind_data(mtcars, keep_real = "cyl", seed = 1)
#' table(arms$cyl) == table(mtcars$cyl)
blind_data <- function(data, blind_names = FALSE, keep_labels = FALSE,
                       keep_real = NULL, rows = NULL, seed = NULL) {
  db_stop_if_not_data(data)
  blind_names <- db_check_flag(blind_names, "blind_names")
  keep_labels <- db_check_flag(keep_labels, "keep_labels")
  keep_real <- db_check_keep_real(keep_real, rows)
  db_check_keep_found(keep_real, names(data))
  n <- db_check_rows(rows, nrow(data))

  specs <- db_mark_kept(db_detect_all(data), keep_real)
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
    if (isTRUE(specs[[i]]$keep_real)) {
      return(data[[i]])
    }
    db_blind_column(data[[i]], specs[[i]], n, keep_labels, names(data)[[i]])
  })
  names(columns) <- names(data)

  if (blind_names) {
    # A kept column keeps its real name too: a real value under the name col_07
    # is of no use to anyone writing code against the copy.
    kept <- vapply(specs, function(s) isTRUE(s$keep_real), logical(1))
    blinded_names <- db_blinded_names(length(columns))
    names(columns)[!kept] <- blinded_names[!kept]
    columns[!kept] <- lapply(columns[!kept], db_drop_label)
  }
  db_rebuild(data, columns, n)
}

# Record on each spec whether its column is to be copied over as it is. Carried
# on the spec because every part that has to know - the blinder, the leak check
# and the summary - already has one.
db_mark_kept <- function(specs, keep_real) {
  for (i in seq_along(specs)) {
    specs[[i]]$keep_real <- names(specs)[[i]] %in% keep_real
  }
  specs
}

db_kept_names <- function(specs) {
  names(specs)[vapply(specs, function(s) isTRUE(s$keep_real), logical(1))]
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

db_check_keep_real <- function(keep_real, rows = NULL) {
  if (is.null(keep_real)) {
    return(character())
  }
  bad <- !is.character(keep_real) || anyNA(keep_real) ||
    !all(nzchar(keep_real))
  if (bad) {
    stop(
      "`keep_real` must be a character vector of column names, or NULL.",
      call. = FALSE
    )
  }
  if (!is.null(rows)) {
    stop(
      "`keep_real` and `rows` cannot be used together.\n",
      "A column kept real stays matched to the rest of its row, which only ",
      "works\nwith the row count of the input.",
      call. = FALSE
    )
  }
  unique(keep_real)
}

# Names only: a column asked for and not found is the user's own name, never a
# value out of the data.
db_check_keep_found <- function(keep_real, available) {
  unknown <- setdiff(keep_real, available)
  if (length(unknown) == 0L) {
    return(invisible(keep_real))
  }
  stop(
    "`keep_real` names ",
    if (length(unknown) == 1L) "a column " else "columns ",
    "that the data does not have: ",
    paste0("\"", unknown, "\"", collapse = ", "), ".",
    call. = FALSE
  )
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
