#' Blind a data file
#'
#' Reads a data file, blinds every column of every sheet, and writes a copy in
#' the same format next to the input, keeping the delimiter, decimal mark,
#' encoding and sheet names of a text file or workbook, and the variable labels
#' and display formats of an SPSS or Stata file. Code written against the copy
#' runs unchanged on the real file.
#'
#' This reduces the risk of disclosing the real data. It is not a formal privacy
#' guarantee: the column names, classes, row count and the broad shape of each
#' column stay visible.
#'
#' @param path Path to a CSV, TSV, Excel, SPSS, Stata, RDS or Parquet file. An
#'   RDS file must hold a data frame. Parquet needs the `arrow` package.
#' @param output Where to write the copy. The default adds `_blinded` to the
#'   input's name. An `.xls` input is written as `.xlsx`, which is the only
#'   Excel format that can be written.
#' @inheritParams blind_data
#'
#' @return A `blind_summary`, printed when called at the console, describing the
#'   blinded file one column at a time. Paste it into a chat to tell an AI what
#'   the data looks like.
#'
#' @inheritSection blind_data What happens to each column
#' @inheritSection blind_data Columns kept real
#' @seealso [blind_data()] to do the same to a data frame.
#' @export
#' @examples
#' csv <- file.path(tempdir(), "cars.csv")
#' write.csv(mtcars, csv, row.names = FALSE)
#' blind_file(csv, seed = 1)
blind_file <- function(path, output = NULL, blind_names = FALSE,
                       keep_labels = FALSE, keep_real = NULL, rows = NULL,
                       seed = NULL) {
  blind_names <- db_check_flag(blind_names, "blind_names")
  keep_labels <- db_check_flag(keep_labels, "keep_labels")
  keep_real <- db_check_keep_real(keep_real, rows)

  source <- db_read(path)
  if (is.null(output)) {
    output <- db_output_path(path)
  }
  # Checked against every sheet at once: a name has to exist somewhere in the
  # workbook, and it is kept on each sheet that has it.
  db_check_keep_found(keep_real, unlist(lapply(source$tables, names)))
  specs <- lapply(source$tables, function(table) {
    db_mark_kept(db_detect_all(table), keep_real)
  })

  # One seed for the whole file, so that two sheets of the same shape do not come
  # out with the same values.
  blinded <- db_with_seed(seed, Map(function(table, spec) {
    if (length(table) == 0L) {
      return(table)
    }
    db_blind_frame(
      table, spec, db_check_rows(rows, nrow(table)), blind_names, keep_labels
    )
  }, source$tables, specs))

  leak <- db_check_leak_tables(source$tables, blinded, specs, keep_labels)
  db_stop_on_leak(leak)

  source$tables <- blinded
  db_write(source, output)

  db_summary(
    tables = Map(
      function(table, spec) db_describe_table(table, spec, keep_labels),
      blinded, specs
    ),
    leak = leak,
    output = output,
    rows = db_row_counts(blinded)
  )
}

# One number for a single table, one per sheet for a workbook.
db_row_counts <- function(tables) {
  counts <- vapply(tables, nrow, integer(1))
  if (length(counts) == 1L) {
    return(unname(counts))
  }
  paste0(names(counts), " ", counts, collapse = ", ")
}
