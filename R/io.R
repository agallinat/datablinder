# Reading and writing data files.
#
# Every reader returns a "source": the tables it found plus the format details
# needed to write the blinded copy back out in the same shape. Nothing in this
# file knows anything about blinding, so that new formats can be added without
# touching detect.R or blinders.R.

# File extensions we recognise, mapped to the internal format name.
DB_EXTENSIONS <- list(
  csv = "csv", txt = "csv",
  tsv = "tsv", tab = "tsv",
  xlsx = "xlsx", xlsm = "xlsx", xls = "xls",
  sav = "sav", zsav = "sav", dta = "dta",
  rds = "rds", parquet = "parquet"
)

# Delimiters tried when sniffing a text file, in order of preference.
DB_DELIMITERS <- c(",", ";", "\t", "|")

# How much of a text file to look at when sniffing its format.
DB_SNIFF_BYTES <- 65536L
DB_SNIFF_LINES <- 50L

# Extensions ------------------------------------------------------------

db_ext <- function(path) {
  base <- basename(path)
  if (!grepl("\\.[^.]+$", base)) {
    return("")
  }
  tolower(sub(".*\\.", "", base))
}

db_file_type <- function(path) {
  type <- DB_EXTENSIONS[[db_ext(path)]]
  if (is.null(type)) {
    stop(
      "Cannot tell the file type of \"", basename(path), "\".\n",
      "Supported extensions: ", paste(names(DB_EXTENSIONS), collapse = ", "),
      ".",
      call. = FALSE
    )
  }
  type
}

#' Default output path for a blinded file
#'
#' `.xls` cannot be written, so an `.xls` input becomes an `.xlsx` output.
#'
#' @param path Path to the input file.
#' @return A path next to the input, with `_blinded` added to the name.
#' @noRd
db_output_path <- function(path) {
  type <- db_file_type(path)
  ext <- if (type == "xls") "xlsx" else db_ext(path)
  paste0(sub("\\.[^.]+$", "", path), "_blinded.", ext)
}

# Dispatch --------------------------------------------------------------

db_read <- function(path) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }
  type <- db_file_type(path)
  switch(type,
    csv = ,
    tsv = db_read_delim(path, type),
    xlsx = ,
    xls = db_read_excel(path, type),
    sav = ,
    dta = db_read_haven(path, type),
    rds = db_read_rds(path),
    parquet = db_read_parquet(path),
    stop("Reading ", type, " files is not supported yet.", call. = FALSE)
  )
}

#' The column names of a data file, without reading its values
#'
#' Only the app needs this: it has to offer the columns before anything has been
#' blinded, and reading a large file twice to do it would be a poor trade. Every
#' reader here stops at the header where the format allows it. RDS is the one
#' that cannot: an R object has to be loaded whole.
#'
#' @param path Path to a data file.
#' @return A character vector of column names, one entry per column of every
#'   sheet, deduplicated.
#' @noRd
db_read_columns <- function(path) {
  if (!file.exists(path)) {
    stop("File not found: ", path, call. = FALSE)
  }
  type <- db_file_type(path)
  names <- switch(type,
    csv = ,
    tsv = names(db_fread(path, db_sniff_delim(path, type), nrows = 0L)),
    xlsx = ,
    xls = unlist(lapply(readxl::excel_sheets(path), function(sheet) {
      names(readxl::read_excel(
        path,
        sheet = sheet, n_max = 0, .name_repair = "minimal", progress = FALSE
      ))
    })),
    sav = names(haven::read_sav(path, n_max = 0)),
    dta = names(haven::read_dta(path, n_max = 0)),
    rds = names(db_read_rds(path)$tables[[1]]),
    parquet = db_parquet_columns(path),
    stop("Reading ", type, " files is not supported yet.", call. = FALSE)
  )
  unique(as.character(names))
}

# open_dataset() reads the footer rather than the columns.
db_parquet_columns <- function(path) {
  db_require_arrow()
  names(arrow::open_dataset(path, format = "parquet"))
}

db_write <- function(source, path) {
  switch(source$type,
    csv = ,
    tsv = db_write_delim(source$tables[[1]], path, source$meta),
    xlsx = ,
    xls = db_write_excel(source$tables, path),
    sav = ,
    dta = db_write_haven(source$tables[[1]], path, source$type),
    rds = db_write_rds(source$tables[[1]], path),
    parquet = db_write_parquet(source$tables[[1]], path),
    stop("Writing ", source$type, " files is not supported yet.", call. = FALSE)
  )
  invisible(path)
}

# Delimited text --------------------------------------------------------

db_read_delim <- function(path, type = db_file_type(path)) {
  meta <- db_sniff_delim(path, type)
  df <- db_fread(path, meta)
  # fread names unheaded columns V1, V2, ...; that is our only clue that the
  # file had no header line, and we must not invent one on the way out.
  meta$header <- !identical(names(df), paste0("V", seq_along(df)))
  list(path = path, type = type, tables = list(data = df), meta = meta)
}

# One fread call for the whole package, so that reading a file's header alone
# cannot name its columns differently from reading the file.
db_fread <- function(path, meta, nrows = Inf) {
  data.table::fread(
    file = path,
    sep = meta$sep,
    dec = meta$dec,
    encoding = meta$encoding,
    na.strings = unique(c("", "NA", meta$na_string)),
    nrows = nrows,
    keepLeadingZeros = TRUE,
    logical01 = FALSE,
    data.table = FALSE,
    check.names = FALSE,
    showProgress = FALSE
  )
}

db_write_delim <- function(x, path, meta) {
  data.table::fwrite(
    x,
    file = path,
    sep = meta$sep,
    dec = meta$dec,
    na = meta$na_string,
    eol = meta$eol,
    bom = meta$bom,
    col.names = meta$header,
    # "" leaves the stored bytes alone, which is what keeps a Latin-1 file
    # Latin-1.
    encoding = if (identical(meta$encoding, "UTF-8")) "UTF-8" else "",
    quote = "auto",
    showProgress = FALSE
  )
  invisible(path)
}

# Sniffing a delimited file ---------------------------------------------

db_sniff_delim <- function(path, type = db_file_type(path)) {
  bytes <- readBin(path, what = "raw", n = DB_SNIFF_BYTES)

  bom <- length(bytes) >= 3L &&
    identical(bytes[1:3], as.raw(c(0xef, 0xbb, 0xbf)))
  if (bom) {
    bytes <- bytes[-(1:3)]
  }

  # Drop a partial last line, so that a multi-byte character cut in half by
  # the read limit cannot be mistaken for a Latin-1 file.
  breaks <- which(bytes == as.raw(0x0a))
  if (length(breaks) > 0L && length(bytes) > breaks[length(breaks)]) {
    bytes <- bytes[seq_len(breaks[length(breaks)])]
  }

  text <- rawToChar(bytes)
  encoding <- if (validUTF8(text)) "UTF-8" else "Latin-1"
  Encoding(text) <- if (encoding == "UTF-8") "UTF-8" else "latin1"

  lines <- strsplit(text, "\n", fixed = TRUE)[[1]]
  eol <- if (length(lines) > 0L && grepl("\r$", lines[[1]])) "\r\n" else "\n"
  lines <- sub("\r$", "", lines)
  lines <- utils::head(lines[nzchar(lines)], DB_SNIFF_LINES)

  sep <- db_sniff_sep(lines, type)
  list(
    sep = sep,
    dec = db_sniff_dec(lines, sep),
    na_string = db_sniff_na(lines, sep),
    encoding = encoding,
    eol = eol,
    bom = bom
  )
}

db_split_fields <- function(line, sep) {
  tryCatch(
    scan(
      text = line, what = "", sep = sep, quote = "\"",
      # we want the fields exactly as written, so "NA" must stay a string
      na.strings = character(), quiet = TRUE,
      blank.lines.skip = FALSE, strip.white = FALSE
    ),
    error = function(e) NULL,
    warning = function(w) NULL
  )
}

db_sniff_sep <- function(lines, type = "csv") {
  default <- if (type == "tsv") "\t" else ","
  if (length(lines) == 0L) {
    return(default)
  }
  counts <- lapply(DB_DELIMITERS, function(sep) {
    vapply(lines, function(line) {
      fields <- db_split_fields(line, sep)
      if (is.null(fields)) NA_integer_ else length(fields)
    }, integer(1), USE.NAMES = FALSE)
  })
  # A delimiter is plausible if it splits every sampled line into the same
  # number of fields, and into more than one.
  ok <- vapply(
    counts,
    function(n) !anyNA(n) && n[[1]] > 1L && all(n == n[[1]]),
    logical(1)
  )
  if (!any(ok)) {
    return(default)
  }
  widths <- vapply(counts[ok], function(n) n[[1]], integer(1))
  DB_DELIMITERS[ok][[which.max(widths)]]
}

db_data_fields <- function(lines, sep) {
  if (length(lines) < 2L) {
    return(character())
  }
  unlist(lapply(lines[-1], db_split_fields, sep = sep), use.names = FALSE)
}

db_sniff_dec <- function(lines, sep) {
  if (sep == ",") {
    return(".")
  }
  fields <- db_data_fields(lines, sep)
  if (any(grepl("^ *[-+]?[0-9]+,[0-9]+ *$", fields))) "," else "."
}

db_sniff_na <- function(lines, sep) {
  fields <- db_data_fields(lines, sep)
  if (sum(fields == "NA") > sum(!nzchar(trimws(fields)))) "NA" else ""
}

# Excel -----------------------------------------------------------------

db_read_excel <- function(path, type = db_file_type(path)) {
  sheets <- readxl::excel_sheets(path)
  tables <- lapply(sheets, function(sheet) {
    readxl::read_excel(
      path,
      sheet = sheet,
      .name_repair = "minimal",
      progress = FALSE
    )
  })
  names(tables) <- sheets
  list(path = path, type = type, tables = tables, meta = list(sheets = sheets))
}

db_write_excel <- function(tables, path) {
  writexl::write_xlsx(tables, path = path)
  invisible(path)
}

# SPSS and Stata --------------------------------------------------------

# haven keeps the value labels, variable labels and display formats as column
# attributes, so there is no format detail to remember here: the attributes
# travel with the columns and blinders.R puts them back.

db_read_haven <- function(path, type = db_file_type(path)) {
  data <- switch(type,
    sav = haven::read_sav(path),
    dta = haven::read_dta(path)
  )
  list(path = path, type = type, tables = list(data = data), meta = list())
}

db_write_haven <- function(x, path, type) {
  switch(type,
    # Compression is read off the output's extension rather than the input's, so
    # that a .zsav written as .sav is a plain .sav.
    sav = haven::write_sav(
      x, path,
      compress = if (db_ext(path) == "zsav") "zsav" else "byte"
    ),
    dta = haven::write_dta(x, path)
  )
  invisible(path)
}

# R objects -------------------------------------------------------------

db_read_rds <- function(path) {
  object <- readRDS(path)
  if (!is.data.frame(object)) {
    stop(
      "The RDS file does not hold a data frame ",
      "(it holds an object of class \"", class(object)[[1L]], "\").\n",
      "datablinder can only blind data frames.",
      call. = FALSE
    )
  }
  list(path = path, type = "rds", tables = list(data = object), meta = list())
}

db_write_rds <- function(x, path) {
  saveRDS(x, path)
  invisible(path)
}

# Parquet ---------------------------------------------------------------

db_read_parquet <- function(path) {
  db_require_arrow()
  list(
    path = path, type = "parquet",
    tables = list(data = arrow::read_parquet(path)), meta = list()
  )
}

db_write_parquet <- function(x, path) {
  db_require_arrow()
  arrow::write_parquet(x, path)
  invisible(path)
}

# arrow is a Suggests, so Parquet only works where it is installed.
db_require_arrow <- function() {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop(
      "Parquet files need the arrow package.\n",
      "Install it with install.packages(\"arrow\").",
      call. = FALSE
    )
  }
  invisible(TRUE)
}
