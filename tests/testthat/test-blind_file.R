# All values below are invented.

# A private copy of a fixture, so that the blinded file lands in the temp
# directory and not next to the fixtures.
staged <- function(fixture) {
  path <- tmp_path(fixture)
  file.copy(test_path("fixtures", fixture), path, overwrite = TRUE)
  path
}

# Whole files ------------------------------------------------------------

test_that("a csv is blinded into a copy next to the input", {
  path <- staged("comma.csv")
  summary <- blind_file(path, seed = 1)

  expect_equal(summary$output, sub("comma\\.csv$", "comma_blinded.csv", path))
  expect_true(file.exists(summary$output))
  expect_s3_class(summary, "blind_summary")
})

test_that("the blinded copy has the same columns, classes and row count", {
  path <- staged("comma.csv")
  blinded <- db_read(blind_file(path, seed = 1)$output)
  real <- db_read(path)

  expect_equal(names(blinded$tables$data), names(real$tables$data))
  expect_equal(col_classes(blinded$tables$data), col_classes(real$tables$data))
  expect_equal(nrow(blinded$tables$data), nrow(real$tables$data))
})

test_that("the delimiter, decimal mark and missing-value text are kept", {
  path <- staged("semicolon.csv")
  meta <- db_read(blind_file(path, seed = 1)$output)$meta
  expect_equal(meta$sep, ";")
  expect_equal(meta$dec, ",")
  expect_equal(meta$na_string, "NA")
})

test_that("a Latin-1 file keeps its encoding and line endings", {
  # The accented values only reach the copy when the labels are kept; with
  # keep_labels = FALSE the copy is pure ASCII, which reads correctly as either
  # encoding, so there is nothing left to tell them apart.
  path <- staged("latin1.csv")
  meta <- db_read(blind_file(path, keep_labels = TRUE, seed = 1)$output)$meta
  expect_equal(meta$encoding, "Latin-1")
  expect_equal(meta$eol, "\r\n")
})

test_that("line endings survive even when the copy is pure ASCII", {
  path <- staged("latin1.csv")
  output <- blind_file(path, seed = 1)$output
  expect_equal(db_read(output)$meta$eol, "\r\n")
  expect_true(validUTF8(rawToChar(file_bytes(output))))
})

test_that("a byte order mark is kept", {
  path <- staged("bom.csv")
  expect_true(db_read(blind_file(path, seed = 1)$output)$meta$bom)
})

test_that("a tsv stays tab separated", {
  path <- staged("tabs.tsv")
  output <- blind_file(path, seed = 1)$output
  expect_match(output, "_blinded\\.tsv$")
  expect_equal(db_read(output)$meta$sep, "\t")
})

test_that("every sheet of a workbook is blinded, sheet names kept", {
  path <- staged("two_sheets.xlsx")
  real <- db_read(path)
  blinded <- db_read(blind_file(path, seed = 1)$output)

  expect_equal(names(blinded$tables), names(real$tables))
  for (sheet in c("patients", "visits")) {
    expect_equal(names(blinded$tables[[sheet]]), names(real$tables[[sheet]]), info = sheet)
    expect_equal(
      col_classes(blinded$tables[[sheet]]), col_classes(real$tables[[sheet]]),
      info = sheet
    )
    expect_equal(nrow(blinded$tables[[sheet]]), nrow(real$tables[[sheet]]), info = sheet)
  }
})

test_that("two sheets of the same shape do not come out identical", {
  path <- tmp_path("twins.xlsx")
  sheet <- data.frame(
    id = sprintf("P-%06d", 1:20),
    score = round(seq(1.5, 20.5, length.out = 20L), 2L),
    stringsAsFactors = FALSE
  )
  writexl::write_xlsx(list(first = sheet, second = sheet), path)

  blinded <- db_read(blind_file(path, seed = 1)$output)$tables
  expect_false(identical(blinded$first$id, blinded$second$id))
  expect_false(identical(blinded$first$score, blinded$second$score))
})

test_that("no real value from the file appears in the copy", {
  for (fixture in c("comma.csv", "semicolon.csv", "tabs.tsv", "latin1.csv")) {
    path <- staged(fixture)
    real <- db_read(path)$tables$data
    blinded <- db_read(blind_file(path, seed = 1)$output)$tables$data
    for (column in names(real)[vapply(real, is.character, logical(1))]) {
      # missing values are in both by design, so compare what is present
      expect_equal(
        intersect(db_present(blinded[[column]]), db_present(real[[column]])),
        character(),
        info = paste(fixture, column)
      )
    }
  }
})

# SPSS and Stata ---------------------------------------------------------

test_that("an SPSS or Stata file keeps its columns, classes and codes", {
  for (fixture in c("labelled.sav", "labelled.dta")) {
    path <- staged(fixture)
    real <- db_read(path)$tables$data
    blinded <- db_read(blind_file(path, seed = 1)$output)$tables$data

    expect_equal(names(blinded), names(real), info = fixture)
    expect_equal(col_classes(blinded), col_classes(real), info = fixture)
    expect_equal(nrow(blinded), nrow(real), info = fixture)
    # The codes of a labelled column are kept on purpose: code written against
    # the copy compares against them.
    expect_true(all(db_present(db_bare(blinded$sex)) %in% c(1, 2)), info = fixture)
  }
})

test_that("value labels are relabelled by default and kept on request", {
  for (fixture in c("labelled.sav", "labelled.dta")) {
    path <- staged(fixture)

    blinded <- db_read(blind_file(path, seed = 1)$output)$tables$data
    expect_equal(names(attr(blinded$sex, "labels")), c("A", "B"), info = fixture)
    expect_equal(
      names(attr(blinded$region, "labels")), c("A", "B", "C"),
      info = fixture
    )

    kept <- db_read(
      blind_file(path, output = tmp_path(paste0("kept-", fixture)),
        keep_labels = TRUE, seed = 1
      )$output
    )$tables$data
    expect_equal(
      names(attr(kept$sex, "labels")), c("Male", "Female"),
      info = fixture
    )
  }
})

test_that("variable labels and display formats survive, and blind_names drops labels", {
  path <- staged("labelled.sav")
  blinded <- db_read(blind_file(path, seed = 1)$output)$tables$data
  expect_equal(attr(blinded$age, "label"), "Age in years")
  expect_equal(attr(blinded$visit_date, "format.spss"), "DATE11")

  renamed <- db_read(
    blind_file(path,
      output = tmp_path("renamed.sav"), blind_names = TRUE, seed = 1
    )$output
  )$tables$data
  expect_named(renamed, sprintf("col_%02d", 1:7))
  expect_null(attr(renamed$col_02, "label"))

  stata <- db_read(blind_file(staged("labelled.dta"), seed = 1)$output)$tables$data
  expect_equal(attr(stata$visit_date, "format.stata"), "%td")
  expect_equal(attr(stata$age, "label"), "Age in years")
})

# RDS --------------------------------------------------------------------

test_that("an rds file is blinded into an rds file of the same shape", {
  path <- staged("table.rds")
  real <- readRDS(path)
  summary <- blind_file(path, seed = 1)

  expect_match(summary$output, "_blinded\\.rds$")
  blinded <- readRDS(summary$output)
  expect_s3_class(blinded, "data.frame")
  expect_equal(names(blinded), names(real))
  expect_equal(col_classes(blinded), col_classes(real))
  expect_equal(nrow(blinded), nrow(real))
  expect_equal(nlevels(blinded$grade), nlevels(real$grade))
  expect_true(is.ordered(blinded$grade))
})

test_that("a tibble or data.table in an rds file comes back as one", {
  skip_if_not_installed("tibble")
  real <- readRDS(test_path("fixtures", "table.rds"))

  for (object in list(tibble::as_tibble(real), data.table::as.data.table(real))) {
    path <- tmp_path("classed-in.rds")
    saveRDS(object, path)
    blinded <- readRDS(blind_file(path, seed = 1)$output)
    expect_equal(class(blinded), class(object))
    expect_equal(names(blinded), names(object))
  }
})

test_that("an rds file that is not a data frame is refused", {
  path <- tmp_path("model.rds")
  saveRDS(stats::lm(mpg ~ cyl, data = mtcars), path)
  expect_error(blind_file(path), "does not hold a data frame")
})

# Parquet ----------------------------------------------------------------

test_that("a parquet file is blinded into a parquet file of the same shape", {
  skip_if_not_installed("arrow")
  real <- readRDS(test_path("fixtures", "table.rds"))
  path <- tmp_path("clinic.parquet")
  arrow::write_parquet(real, path)

  summary <- blind_file(path, seed = 1)
  expect_match(summary$output, "_blinded\\.parquet$")

  blinded <- arrow::read_parquet(summary$output)
  expect_equal(names(blinded), names(real))
  expect_equal(col_classes(blinded), col_classes(real))
  expect_equal(nrow(blinded), nrow(real))
  expect_true(is.ordered(blinded$grade))
})

# No leaks, on every fixture ---------------------------------------------

test_that("no real text value reaches the copy of a labelled or R file", {
  for (fixture in c("labelled.sav", "labelled.dta", "table.rds")) {
    path <- staged(fixture)
    real <- db_read(path)$tables$data
    blinded <- db_read(blind_file(path, seed = 1)$output)$tables$data
    for (column in names(real)[vapply(real, is.character, logical(1))]) {
      expect_equal(
        intersect(db_present(blinded[[column]]), db_present(real[[column]])),
        character(),
        info = paste(fixture, column)
      )
    }
  }
})

# Options ----------------------------------------------------------------

test_that("output chooses where the copy goes", {
  path <- staged("comma.csv")
  elsewhere <- tmp_path("chosen-name.csv")
  summary <- blind_file(path, output = elsewhere, seed = 1)
  expect_equal(summary$output, elsewhere)
  expect_true(file.exists(elsewhere))
})

test_that("rows applies to every sheet", {
  path <- staged("two_sheets.xlsx")
  blinded <- db_read(blind_file(path, rows = 25L, seed = 1)$output)$tables
  expect_equal(nrow(blinded$patients), 25L)
  expect_equal(nrow(blinded$visits), 25L)
})

test_that("blind_names renames the columns of every sheet", {
  path <- staged("two_sheets.xlsx")
  blinded <- db_read(blind_file(path, blind_names = TRUE, seed = 1)$output)$tables
  expect_named(blinded$patients, sprintf("col_%02d", 1:4))
  expect_named(blinded$visits, sprintf("col_%02d", 1:3))
})

test_that("the same seed gives the same file", {
  path <- staged("comma.csv")
  first <- tmp_path("seeded-a.csv")
  second <- tmp_path("seeded-b.csv")
  blind_file(path, output = first, seed = 9)
  blind_file(path, output = second, seed = 9)
  expect_equal(file_bytes(first), file_bytes(second))

  third <- tmp_path("seeded-c.csv")
  blind_file(path, output = third, seed = 10)
  expect_false(identical(file_bytes(first), file_bytes(third)))
})

test_that("blinding a file leaves the session's RNG state alone", {
  set.seed(77)
  runif(1)
  before <- .Random.seed
  blind_file(staged("comma.csv"), seed = 1)
  blind_file(staged("comma.csv"), seed = NULL)
  expect_identical(.Random.seed, before)
})

# Errors -----------------------------------------------------------------

test_that("a missing file and an unknown format are refused clearly", {
  expect_error(blind_file(tmp_path("nowhere.csv")), "File not found")
  notes <- tmp_path("notes.docx")
  file.create(notes)
  expect_error(blind_file(notes), "Cannot tell the file type")
})

test_that("bad options are refused before anything is read", {
  path <- staged("comma.csv")
  expect_error(blind_file(path, rows = 0L), "`rows`")
  expect_error(blind_file(path, blind_names = "yes"), "`blind_names`")
})

# The success criterion, through a file ----------------------------------

test_that("an analysis written for the blinded file runs on the real file", {
  path <- tmp_path("clinic.csv")
  real <- data.frame(
    patient_id = sprintf("P-%06d", 1:200),
    age = as.integer(20L + seq_len(200L) %% 60L),
    score = round(seq(1.5, 20.5, length.out = 200L), 2L),
    arm = rep(c("control", "treatment"), times = 100L),
    visit = format(as.Date("2021-01-01") + seq_len(200L), "%d/%m/%Y"),
    stringsAsFactors = FALSE
  )
  data.table::fwrite(real, path)

  blinded <- db_read(blind_file(path, seed = 1)$output)$tables$data

  analyse <- function(data) {
    data$visit <- as.Date(data$visit, format = "%d/%m/%Y")
    by_arm <- tapply(data$score, data$arm, mean)
    model <- stats::lm(score ~ age, data = data)
    list(
      groups = length(by_arm),
      months = length(unique(format(data$visit, "%m"))),
      coefficients = names(stats::coef(model)),
      ids = length(unique(data$patient_id))
    )
  }

  on_blinded <- analyse(blinded)
  expect_no_error(on_real <- analyse(db_read(path)$tables$data))
  expect_equal(on_blinded$groups, on_real$groups)
  expect_equal(on_blinded$coefficients, on_real$coefficients)
  expect_equal(on_blinded$ids, on_real$ids)
})
