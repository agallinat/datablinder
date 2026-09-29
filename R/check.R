# The leak check.
#
# Run after every blinding, before anything is written. Which columns are held
# to which standard depends on how their blinded values were made:
#
#  forbid    The new values were built from the shape of the real ones, so an
#            overlap is informative and must never happen. Guaranteed by
#            construction in blinders.R; checking it here is the safety net.
#  canonical Categories are relabelled A, B, C... Those labels are a constant of
#            the package, not something derived from the data, so comparing them
#            with the real labels measures nothing. What matters is that the
#            relabelling happened at all, which is what is checked.
#  count     An overlap is a coincidence that carries no information: a rounded
#            numeric column has only so many possible values, a date range is
#            shifted rather than moved, and placeholder words come from a fixed
#            list. Counted and reported, as SPEC.md section 6 asks.
#  none      Overlap is what was asked for: the same set of discrete values, the
#            same share of TRUE, a constant number kept, or labels kept on
#            purpose.
#  kept      keep_real asked for the real column. There is nothing to check: the
#            values are the real ones by definition. The column is named in the
#            report instead, so that the summary can say so out loud rather than
#            let a bare "passed" imply more than it means.

DB_LEAK_FORBID <- "forbid"
DB_LEAK_CANONICAL <- "canonical"
DB_LEAK_COUNT <- "count"
DB_LEAK_NONE <- "none"
DB_LEAK_KEPT <- "kept"

# Types whose labels are replaced by A, B, C...
DB_LABEL_TYPES <- c("factor", "category_text", "labelled")

db_leak_rule <- function(type, numeric, keep_labels, keep_real = FALSE) {
  if (isTRUE(keep_real)) {
    return(DB_LEAK_KEPT)
  }
  if (type %in% DB_LABEL_TYPES) {
    return(if (keep_labels) DB_LEAK_NONE else DB_LEAK_CANONICAL)
  }
  switch(type,
    all_na = DB_LEAK_NONE,
    logical = DB_LEAK_NONE,
    numeric_discrete = DB_LEAK_NONE,
    constant = if (numeric || keep_labels) DB_LEAK_NONE else DB_LEAK_FORBID,
    numeric_continuous = DB_LEAK_COUNT,
    date = DB_LEAK_COUNT,
    date_text = DB_LEAK_COUNT,
    free_text = DB_LEAK_COUNT,
    DB_LEAK_FORBID
  )
}

#' Check a blinded table against the real one
#'
#' @param real,blinded The real and blinded tables, same columns in the same
#'   order.
#' @param specs Specs from `db_detect_all()` on the real table.
#' @param keep_labels Were real category labels kept on purpose?
#' @return A list with `passed`, the names of any `leaked` columns, `matches`,
#'   one count per column where a coincidence is possible, and `kept`, the
#'   columns `keep_real` excused from the check.
#' @noRd
db_check_leaks <- function(real, blinded, specs, keep_labels = FALSE) {
  leaked <- character()
  matches <- integer()
  kept <- character()

  for (i in seq_along(specs)) {
    type <- specs[[i]]$type
    rule <- db_leak_rule(
      type, is.numeric(real[[i]]), keep_labels, specs[[i]]$keep_real
    )
    name <- names(real)[[i]]

    if (rule == DB_LEAK_KEPT) {
      kept <- c(kept, name)
    } else if (rule == DB_LEAK_FORBID) {
      overlap <- intersect(
        db_comparable(blinded[[i]], type),
        db_comparable(real[[i]], type)
      )
      if (length(overlap) > 0L) {
        leaked <- c(leaked, name)
      }
    } else if (rule == DB_LEAK_CANONICAL) {
      # Every blinded label must be one of the A, B, C... labels the real
      # column's size allows. A subset test rather than equality, because with
      # fewer rows than categories not every label gets used.
      expected <- db_level_labels(length(db_labels_of(real[[i]], type)))
      if (!all(db_labels_of(blinded[[i]], type) %in% expected)) {
        leaked <- c(leaked, name)
      }
    } else if (rule == DB_LEAK_COUNT) {
      found <- db_comparable(blinded[[i]], type) %in% db_comparable(real[[i]], type)
      matches[[name]] <- sum(found)
    }
  }

  list(
    passed = length(leaked) == 0L, leaked = leaked, matches = matches,
    kept = kept
  )
}

# The same check over every sheet of a workbook. Counts keep their sheet name, so
# that a coincidence can be traced back to the sheet it happened on.
db_check_leak_tables <- function(real, blinded, specs, keep_labels = FALSE) {
  reports <- lapply(seq_along(real), function(i) {
    db_check_leaks(real[[i]], blinded[[i]], specs[[i]], keep_labels)
  })
  names(reports) <- names(real)
  list(
    passed = all(vapply(reports, function(r) r$passed, logical(1))),
    leaked = unlist(lapply(reports, function(r) r$leaked), use.names = FALSE),
    matches = unlist(lapply(reports, function(r) r$matches)),
    # One name per column, not per sheet: the same column kept on three sheets is
    # one thing for the reader to weigh, not three.
    kept = as.character(unique(unlist(
      lapply(reports, function(r) r$kept),
      use.names = FALSE
    )))
  )
}

# Every value, for counting coincidences and for spotting overlaps. Dates and
# numbers are compared as numbers, and labelled columns by their labels, as the
# codes themselves are kept on purpose.
db_comparable <- function(x, type) {
  if (type == "labelled") {
    return(names(attr(x, "labels")))
  }
  if (type %in% c("numeric_continuous", "numeric_discrete", "date")) {
    return(db_present(db_bare(x)))
  }
  as.character(db_present(x))
}

# The set of labels a categorical column uses.
db_labels_of <- function(x, type) {
  if (type == "labelled") {
    return(names(attr(x, "labels")))
  }
  if (type == "factor") {
    return(levels(x))
  }
  sort(unique(as.character(db_present(x))))
}

# Names columns only: no real value is ever put in an error message.
db_stop_on_leak <- function(leak) {
  if (leak$passed) {
    return(invisible(NULL))
  }
  stop(
    "Leak check failed on ",
    if (length(leak$leaked) == 1L) "column " else "columns ",
    paste0("\"", leak$leaked, "\"", collapse = ", "), ".\n",
    "Nothing has been written. Please report this as a bug.",
    call. = FALSE
  )
}
