# Fixture values are invented, so it is safe to name them here.

# File types and output paths --------------------------------------------

test_that("db_file_type recognises the supported extensions", {
  expect_equal(db_file_type("a.csv"), "csv")
  expect_equal(db_file_type("a.TXT"), "csv")
  expect_equal(db_file_type("a.tsv"), "tsv")
  expect_equal(db_file_type("a.xlsx"), "xlsx")
  expect_equal(db_file_type("a.xls"), "xls")
  expect_equal(db_file_type("a.sav"), "sav")
  expect_equal(db_file_type("a.dta"), "dta")
  expect_equal(db_file_type("a.rds"), "rds")
  expect_equal(db_file_type("a.parquet"), "parquet")
})

test_that("an unknown extension gives a clear error", {
  expect_error(db_file_type("notes.docx"), "Cannot tell the file type")
  expect_error(db_file_type("noextension"), "Cannot tell the file type")
})

test_that("db_output_path adds _blinded next to the input", {
  expect_equal(db_output_path("patients.csv"), "patients_blinded.csv")
  expect_equal(
    db_output_path("/data/2024/patients.v2.xlsx"),
    "/data/2024/patients.v2_blinded.xlsx"
  )
  # .xls cannot be written, so the copy is .xlsx
  expect_equal(db_output_path("old.xls"), "old_blinded.xlsx")
})

test_that("a missing file gives a clear error", {
  expect_error(db_read(tmp_path("does-not-exist.csv")), "File not found")
})

# Sniffing --------------------------------------------------------------

test_that("the format of a comma separated file is recognised", {
  meta <- db_sniff_delim(test_path("fixtures", "comma.csv"))
  expect_equal(meta$sep, ",")
  expect_equal(meta$dec, ".")
  expect_equal(meta$na_string, "")
  expect_equal(meta$encoding, "UTF-8")
  expect_equal(meta$eol, "\n")
  expect_false(meta$bom)
})

test_that("semicolons with a decimal comma and literal NA are recognised", {
  meta <- db_sniff_delim(test_path("fixtures", "semicolon.csv"))
  expect_equal(meta$sep, ";")
  expect_equal(meta$dec, ",")
  expect_equal(meta$na_string, "NA")
})

test_that("tabs are recognised", {
  meta <- db_sniff_delim(test_path("fixtures", "tabs.tsv"))
  expect_equal(meta$sep, "\t")
  expect_equal(meta$dec, ".")
})

test_that("a Latin-1 file with CRLF endings is recognised", {
  meta <- db_sniff_delim(test_path("fixtures", "latin1.csv"))
  expect_equal(meta$encoding, "Latin-1")
  expect_equal(meta$eol, "\r\n")
  expect_false(meta$bom)
})

test_that("a byte order mark is recognised and does not confuse the sniffer", {
  meta <- db_sniff_delim(test_path("fixtures", "bom.csv"))
  expect_true(meta$bom)
  expect_equal(meta$encoding, "UTF-8")
  expect_equal(meta$sep, ",")
  expect_equal(meta$eol, "\r\n")
})

test_that("a separator inside a quoted field is not mistaken for the delimiter", {
  path <- tmp_path("quoted.csv")
  writeLines(c(
    "id;town",
    "1;\"Paris; Texas\"",
    "2;\"Bonn\""
  ), path)
  expect_equal(db_sniff_delim(path)$sep, ";")
})

test_that("a single column file falls back to the extension's delimiter", {
  csv <- tmp_path("one-column.csv")
  writeLines(c("id", "1", "2"), csv)
  expect_equal(db_sniff_delim(csv)$sep, ",")

  tsv <- tmp_path("one-column.tsv")
  writeLines(c("id", "1", "2"), tsv)
  expect_equal(db_sniff_delim(tsv, "tsv")$sep, "\t")
})

# Reading delimited files ------------------------------------------------

test_that("a comma separated file is read with its column names and classes", {
  source <- db_read(test_path("fixtures", "comma.csv"))
  data <- source$tables$data

  expect_equal(source$type, "csv")
  expect_named(source$tables, "data")
  expect_equal(
    names(data),
    c("id", "age", "score", "sex", "visit_date", "notes")
  )
  expect_equal(nrow(data), 4L)
  expect_s3_class(data, "data.frame")
  expect_equal(unname(col_classes(data)[c("id", "age", "score")]),
    c("character", "integer", "numeric")
  )
  expect_true(source$meta$header)
})

test_that("blank and literal NA fields both become missing values", {
  comma <- db_read(test_path("fixtures", "comma.csv"))$tables$data
  expect_equal(which(is.na(comma$age)), 2L)
  expect_equal(which(is.na(comma$notes)), 2L)

  semicolon <- db_read(test_path("fixtures", "semicolon.csv"))$tables$data
  expect_equal(which(is.na(semicolon$age)), 2L)
  expect_equal(which(is.na(semicolon$sex)), 3L)
})

test_that("a decimal comma is read as a number, not as text", {
  data <- db_read(test_path("fixtures", "semicolon.csv"))$tables$data
  expect_type(data$score, "double")
  expect_equal(data$score, c(12.5, 9.75, 10.2))
})

test_that("accented text survives a Latin-1 file", {
  data <- db_read(test_path("fixtures", "latin1.csv"))$tables$data
  expect_equal(nchar(data$ville), c(5L, 7L))
  expect_true(all(grepl("^[NR]", data$ville)))
})

test_that("leading zeros stay character", {
  path <- tmp_path("codes.csv")
  writeLines(c("postcode,n", "01234,1", "00987,2"), path)
  data <- db_read(path)$tables$data
  expect_type(data$postcode, "character")
  expect_equal(nchar(data$postcode), c(5L, 5L))
})

test_that("0/1 columns are read as numbers, not as logicals", {
  path <- tmp_path("binary.csv")
  writeLines(c("am,vs", "0,1", "1,0", "1,1"), path)
  data <- db_read(path)$tables$data
  expect_type(data$am, "integer")
  expect_type(data$vs, "integer")
})

test_that("duplicated column names are kept as they are", {
  path <- tmp_path("duplicated.csv")
  writeLines(c("x,x,y", "1,2,3", "4,5,6"), path)
  data <- db_read(path)$tables$data
  expect_equal(names(data), c("x", "x", "y"))
})

# Round trips -----------------------------------------------------------

text_fixtures <- c("comma.csv", "semicolon.csv", "tabs.tsv", "latin1.csv", "bom.csv")

test_that("reading and writing a text file preserves its shape and format", {
  for (fixture in text_fixtures) {
    source <- db_read(test_path("fixtures", fixture))
    out <- tmp_path(paste0("roundtrip-", fixture))
    db_write(source, out)
    again <- db_read(out)

    expect_equal(again$meta, source$meta, info = fixture)
    expect_equal(names(again$tables$data), names(source$tables$data), info = fixture)
    expect_equal(col_classes(again$tables$data), col_classes(source$tables$data),
      info = fixture
    )
    expect_equal(again$tables$data, source$tables$data, info = fixture)
  }
})

test_that("a text file is rewritten byte for byte", {
  # semicolon.csv is left out on purpose: writing "NA" for missing values makes
  # fwrite quote character fields, so a literal "NA" stays distinguishable from
  # a missing one. The delimiter, decimal mark and encoding are still kept.
  for (fixture in setdiff(text_fixtures, "semicolon.csv")) {
    path <- test_path("fixtures", fixture)
    out <- tmp_path(paste0("bytes-", fixture))
    db_write(db_read(path), out)
    expect_equal(file_bytes(out), file_bytes(path), info = fixture)
  }
})

test_that("a file without a header line does not gain one", {
  path <- tmp_path("headerless.csv")
  writeLines(c("1,2,3", "4,5,6"), path)
  source <- db_read(path)
  expect_false(source$meta$header)

  out <- tmp_path("headerless-out.csv")
  db_write(source, out)
  expect_equal(readLines(out), c("1,2,3", "4,5,6"))
})

# Excel ------------------------------------------------------------------

test_that("every sheet of a workbook is read, in order", {
  source <- db_read(test_path("fixtures", "two_sheets.xlsx"))
  expect_equal(source$type, "xlsx")
  expect_equal(names(source$tables), c("patients", "visits", "empty"))
  expect_equal(source$meta$sheets, c("patients", "visits", "empty"))
  expect_equal(names(source$tables$patients), c("id", "age", "score", "sex"))
  expect_equal(names(source$tables$visits), c("id", "visit", "seen"))
  expect_equal(nrow(source$tables$patients), 3L)
  expect_type(source$tables$visits$seen, "logical")
  expect_equal(which(is.na(source$tables$patients$age)), 2L)
})

test_that("a workbook is rewritten with the same sheets, columns and classes", {
  source <- db_read(test_path("fixtures", "two_sheets.xlsx"))
  out <- tmp_path("roundtrip-two_sheets.xlsx")
  db_write(source, out)
  again <- db_read(out)

  expect_equal(names(again$tables), names(source$tables))
  for (sheet in names(source$tables)) {
    expect_equal(
      names(again$tables[[sheet]]), names(source$tables[[sheet]]),
      info = sheet
    )
    expect_equal(
      col_classes(again$tables[[sheet]]), col_classes(source$tables[[sheet]]),
      info = sheet
    )
    expect_equal(
      nrow(again$tables[[sheet]]), nrow(source$tables[[sheet]]),
      info = sheet
    )
  }
})

test_that("duplicated column names in a sheet are kept", {
  path <- tmp_path("duplicated.xlsx")
  sheet <- data.frame(a = 1:2, b = 3:4)
  names(sheet) <- c("x", "x")
  writexl::write_xlsx(list(s1 = sheet), path)

  source <- db_read(path)
  expect_equal(names(source$tables$s1), c("x", "x"))
})

# SPSS and Stata ---------------------------------------------------------

haven_fixtures <- c(sav = "labelled.sav", dta = "labelled.dta")

labelled_columns <- c(
  "patient_id", "age", "sex", "score", "visit_date", "region", "consent"
)

test_that("an SPSS file is read with its labels and display formats", {
  source <- db_read(test_path("fixtures", "labelled.sav"))
  data <- source$tables$data

  expect_equal(source$type, "sav")
  expect_named(source$tables, "data")
  expect_equal(names(data), labelled_columns)
  expect_equal(nrow(data), 6L)
  expect_s3_class(data, "data.frame")

  expect_s3_class(data$sex, "haven_labelled")
  expect_equal(attr(data$sex, "labels"), c(Male = 1, Female = 2))
  expect_equal(attr(data$sex, "label"), "Sex of the patient")
  expect_equal(attr(data$age, "label"), "Age in years")
  expect_equal(attr(data$age, "format.spss"), "F8.2")
  expect_s3_class(data$visit_date, "Date")
})

test_that("a Stata file is read with its labels and display formats", {
  source <- db_read(test_path("fixtures", "labelled.dta"))
  data <- source$tables$data

  expect_equal(source$type, "dta")
  expect_equal(names(data), labelled_columns)
  expect_s3_class(data$region, "haven_labelled")
  expect_equal(attr(data$region, "labels"), c(North = 1, South = 2, East = 3))
  expect_equal(attr(data$region, "label"), "Region of residence")
  expect_equal(attr(data$visit_date, "format.stata"), "%td")
})

test_that("reading and writing an SPSS or Stata file preserves everything", {
  for (fixture in haven_fixtures) {
    source <- db_read(test_path("fixtures", fixture))
    out <- tmp_path(paste0("roundtrip-", fixture))
    db_write(source, out)
    again <- db_read(out)

    expect_equal(names(again$tables$data), names(source$tables$data), info = fixture)
    expect_equal(
      col_classes(again$tables$data), col_classes(source$tables$data),
      info = fixture
    )
    expect_equal(again$tables$data, source$tables$data, info = fixture)
  }
})

test_that("a zsav stays compressed and a zsav written as sav does not", {
  data <- db_read(test_path("fixtures", "labelled.sav"))
  zsav <- tmp_path("compressed.zsav")
  haven::write_sav(data$tables$data, zsav, compress = "zsav")

  expect_equal(db_file_type(zsav), "sav")
  expect_equal(db_output_path(zsav), sub("\\.zsav$", "_blinded.zsav", zsav))

  source <- db_read(zsav)
  again <- tmp_path("compressed-again.zsav")
  db_write(source, again)
  expect_equal(db_read(again)$tables$data, source$tables$data)

  # The extension of the output decides the compression, not the input's.
  plain <- tmp_path("uncompressed.sav")
  db_write(source, plain)
  expect_equal(db_read(plain)$tables$data, source$tables$data)
})

# RDS --------------------------------------------------------------------

test_that("an rds file is read as the data frame it holds", {
  source <- db_read(test_path("fixtures", "table.rds"))
  data <- source$tables$data

  expect_equal(source$type, "rds")
  expect_named(source$tables, "data")
  expect_equal(names(data), c("patient_id", "arm", "grade", "weight", "seen"))
  expect_equal(nrow(data), 6L)
  expect_s3_class(data$arm, "factor")
  expect_true(is.ordered(data$grade))
  expect_equal(nlevels(data$grade), 3L)
})

test_that("an rds file that holds something else gives a clear error", {
  path <- tmp_path("vector.rds")
  saveRDS(1:10, path)
  expect_error(db_read(path), "does not hold a data frame")
  expect_error(db_read(path), "integer")
})

test_that("reading and writing an rds file preserves the object exactly", {
  source <- db_read(test_path("fixtures", "table.rds"))
  out <- tmp_path("roundtrip-table.rds")
  db_write(source, out)
  expect_identical(db_read(out)$tables$data, source$tables$data)
})

test_that("a tibble or data.table in an rds file keeps its class", {
  skip_if_not_installed("tibble")
  data <- db_read(test_path("fixtures", "table.rds"))$tables$data

  for (object in list(tibble::as_tibble(data), data.table::as.data.table(data))) {
    path <- tmp_path("classed.rds")
    saveRDS(object, path)
    source <- db_read(path)
    expect_equal(class(source$tables$data), class(object))

    out <- tmp_path("classed-out.rds")
    db_write(source, out)
    expect_equal(class(db_read(out)$tables$data), class(object))
  }
})

# Parquet ----------------------------------------------------------------

test_that("a parquet file round trips with its columns, classes and rows", {
  skip_if_not_installed("arrow")
  data <- db_read(test_path("fixtures", "table.rds"))$tables$data
  path <- tmp_path("table.parquet")
  arrow::write_parquet(data, path)

  source <- db_read(path)
  expect_equal(source$type, "parquet")
  expect_named(source$tables, "data")
  expect_equal(names(source$tables$data), names(data))
  expect_equal(col_classes(source$tables$data), col_classes(data))
  expect_equal(nrow(source$tables$data), nrow(data))
  expect_true(is.ordered(source$tables$data$grade))

  out <- tmp_path("roundtrip-table.parquet")
  db_write(source, out)
  again <- db_read(out)
  expect_equal(col_classes(again$tables$data), col_classes(source$tables$data))
  expect_equal(again$tables$data, source$tables$data)
})
