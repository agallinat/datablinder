# The command line wrapper.
#
# inst/scripts/datablinder is three lines long: it hands its arguments to
# db_cli() and exits with the status that comes back. Everything the command
# line does lives here instead, so that it can be tested without installing the
# package or starting a second R session. Nothing is parsed twice: the options
# map one to one onto the arguments of blind_file(), and the value checks
# themselves are left to it.

DB_CLI_OK <- 0L
DB_CLI_ERROR <- 1L

DB_CLI_USAGE <- c(
  "Usage: datablinder <file> [options]",
  "",
  "Writes a blinded copy of a CSV, TSV, Excel, SPSS, Stata, RDS or Parquet",
  "file: the same columns, classes and file format, with fake values.",
  "",
  "Options:",
  "  -o, --output <path>  Where to write the copy (default: <name>_blinded.<ext>)",
  "      --blind-names    Rename the columns to col_01, col_02...",
  "      --keep-labels    Keep the real category labels instead of A, B, C...",
  "      --keep-real <cols>  Comma separated columns to copy over WITH THEIR REAL",
  "                       VALUES, unblinded. Cannot be used with --rows",
  "      --rows <n>       Number of rows to generate (default: as many as the input)",
  "      --seed <n>       Seed, for a copy that can be reproduced",
  "  -h, --help           Print this message",
  "  -V, --version        Print the package version",
  "",
  "Example:",
  "  datablinder patients.csv --blind-names --rows 200 --seed 42",
  "  datablinder trial.csv --keep-real arm,visit",
  "",
  "This reduces the risk of disclosing the real data. It is not a formal",
  "privacy guarantee: the column names, classes, row count and the broad shape",
  "of each column stay visible. A column named by --keep-real is shared as it",
  "is: check that it identifies nobody, on its own or beside the others."
)

#' Run the command line wrapper
#'
#' @param args The arguments given to the script, without the R ones.
#' @return An exit status: `0` if the copy was written, `1` if anything went
#'   wrong, the failed leak check included. Printing is a side effect, the
#'   summary on stdout and any complaint on stderr.
#' @noRd
db_cli <- function(args = character()) {
  parsed <- tryCatch(db_cli_parse(args), error = function(e) e)
  if (inherits(parsed, "error")) {
    db_cli_err(c(conditionMessage(parsed), "Try \"datablinder --help\"."))
    return(DB_CLI_ERROR)
  }
  if (parsed$help) {
    db_cli_out(DB_CLI_USAGE)
    return(DB_CLI_OK)
  }
  if (parsed$version) {
    db_cli_out(paste("datablinder", utils::packageVersion("datablinder")))
    return(DB_CLI_OK)
  }

  summary <- tryCatch(
    blind_file(
      path = parsed$path,
      output = parsed$output,
      blind_names = parsed$blind_names,
      keep_labels = parsed$keep_labels,
      keep_real = parsed$keep_real,
      rows = parsed$rows,
      seed = parsed$seed
    ),
    error = function(e) e
  )
  if (inherits(summary, "error")) {
    db_cli_err(conditionMessage(summary))
    return(DB_CLI_ERROR)
  }
  db_cli_out(format(summary))
  DB_CLI_OK
}

# Parsing ----------------------------------------------------------------

db_cli_parse <- function(args) {
  args <- db_cli_split(args)
  parsed <- list(
    path = NULL, output = NULL, blind_names = FALSE, keep_labels = FALSE,
    keep_real = NULL, rows = NULL, seed = NULL, help = FALSE, version = FALSE
  )

  i <- 1L
  while (i <= length(args)) {
    switch(args[[i]],
      "-h" = ,
      "--help" = parsed$help <- TRUE,
      "-V" = ,
      "--version" = parsed$version <- TRUE,
      "--blind-names" = parsed$blind_names <- TRUE,
      "--keep-labels" = parsed$keep_labels <- TRUE,
      "-o" = ,
      "--output" = {
        parsed$output <- db_cli_value(args, i)
        i <- i + 1L
      },
      "--keep-real" = {
        parsed$keep_real <- db_cli_columns(args, i)
        i <- i + 1L
      },
      "--rows" = {
        parsed$rows <- db_cli_number(args, i)
        i <- i + 1L
      },
      "--seed" = {
        parsed$seed <- db_cli_number(args, i)
        i <- i + 1L
      },
      parsed$path <- db_cli_path(parsed$path, args[[i]])
    )
    i <- i + 1L
  }

  if (is.null(parsed$path) && !parsed$help && !parsed$version) {
    stop("No input file given.", call. = FALSE)
  }
  parsed
}

# Accept --rows=200 as well as --rows 200.
db_cli_split <- function(args) {
  pieces <- lapply(args, function(arg) {
    if (grepl("^--[^=]+=", arg)) {
      c(sub("=.*$", "", arg), sub("^[^=]*=", "", arg))
    } else {
      arg
    }
  })
  as.character(unlist(pieces))
}

db_cli_value <- function(args, i) {
  if (i == length(args)) {
    stop("Option \"", args[[i]], "\" needs a value.", call. = FALSE)
  }
  args[[i + 1L]]
}

db_cli_number <- function(args, i) {
  value <- db_cli_value(args, i)
  number <- suppressWarnings(as.numeric(value))
  if (is.na(number) || number != round(number)) {
    stop("Option \"", args[[i]], "\" needs a whole number.", call. = FALSE)
  }
  number
}

# A comma separated list of column names. Surrounding spaces are trimmed, so
# that --keep-real "arm, visit" works as well as --keep-real arm,visit, and a
# name containing a comma cannot be given here: it is a limitation of the
# command line only, and blind_file() takes any name.
db_cli_columns <- function(args, i) {
  names <- trimws(strsplit(db_cli_value(args, i), ",", fixed = TRUE)[[1]])
  names <- names[nzchar(names)]
  if (length(names) == 0L) {
    stop("Option \"", args[[i]], "\" needs at least one column name.",
      call. = FALSE
    )
  }
  names
}

db_cli_path <- function(current, arg) {
  if (startsWith(arg, "-")) {
    stop("Unknown option \"", arg, "\".", call. = FALSE)
  }
  if (!is.null(current)) {
    stop("Only one file can be blinded at a time.", call. = FALSE)
  }
  arg
}

# Printing ---------------------------------------------------------------

db_cli_out <- function(lines) {
  cat(paste0(lines, "\n"), sep = "")
}

db_cli_err <- function(lines) {
  cat(paste0(lines, "\n"), sep = "", file = stderr())
}
