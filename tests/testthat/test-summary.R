# All values below are invented.

described <- function(x, name = "", keep_labels = FALSE, n = length(x)) {
  spec <- db_detect(x, name)
  blinded <- db_with_seed(1, db_blind_column(x, spec, n, keep_labels, name))
  db_describe(blinded, spec, keep_labels)
}

# One line per column ----------------------------------------------------

test_that("each type gets a description of the blinded column", {
  expect_equal(described(rep(NA_real_, 10L)), "all values missing")
  expect_equal(described(rep(7, 10L)), "constant, real value kept")
  expect_equal(described(rep("TRIAL-A", 10L)), "constant, replaced")
  expect_equal(described(rep(c(TRUE, FALSE), 10L)), "logical, similar share of TRUE")
  expect_equal(described(rep(c(4, 6, 8), 10L)), "discrete numbers, same values")
  expect_equal(described(seq(1.5, 30.5, length.out = 40L)), "numeric, synthetic values")
  expect_equal(described(as.Date("2021-01-01") + 1:40), "synthetic dates")
  expect_equal(
    described(sprintf("person%02d@somewhere.example", 1:40)),
    "fake addresses at example.com"
  )
  expect_equal(
    described(sprintf("https://somewhere.example/p%02d", 1:40)),
    "fake URLs at example.com"
  )
  expect_equal(
    described(paste("a handwritten note number", 1:40, "about the visit")),
    "placeholder words, similar length"
  )
})

test_that("a factor is described by its blinded levels", {
  x <- factor(rep(c("north", "south", "east"), length.out = 40L))
  expect_equal(described(x), "3 levels -> A, B, C")
})

test_that("a character category is described by its blinded values", {
  x <- rep(c("yes", "no"), times = 20L)
  expect_equal(described(x), "2 categories -> A, B")
})

test_that("a long list of labels trails off", {
  x <- factor(rep(paste0("level", 1:20), times = 3L))
  note <- described(x)
  expect_match(note, "^20 levels -> A, B, C, D, E, F, \\.\\.\\.$")
})

test_that("one label reads in the singular", {
  x <- factor(rep("only", 10L))
  expect_equal(described(x), "1 level -> A")
})

test_that("kept labels are counted but never named", {
  # printing them would put real values in the console
  x <- factor(rep(c("north", "south"), times = 20L))
  expect_equal(described(x, keep_labels = TRUE), "2 levels kept")
  expect_false(grepl("north", described(x, keep_labels = TRUE)))

  y <- rep(c("yes", "no", "maybe"), times = 20L)
  expect_equal(described(y, keep_labels = TRUE), "3 categories kept")
})

test_that("a text date names its format", {
  x <- format(as.Date("2021-01-01") + 1:40, "%d/%m/%Y")
  expect_equal(described(x), "synthetic dates, format %d/%m/%Y")
})

test_that("shapes are shown with digits as zeros and no real characters", {
  expect_equal(
    described(sprintf("P-%06d", 1:40), name = "patient_id"),
    "new IDs, same shape (A-000000)"
  )
  expect_equal(
    described(rep(c("75011", "13006", "69002"), times = 10L), name = "postcode"),
    "new codes, same shape (00000)"
  )
  expect_equal(
    described(sprintf("+33 6 12 34 %02d 99", 1:40)),
    "fake numbers, same shape (+00 0 00 00 00 00)"
  )
})

test_that("a described table has one row per column, in order", {
  data <- data.frame(
    id = sprintf("P-%06d", 1:40),
    age = as.integer(20:59),
    stringsAsFactors = FALSE
  )
  specs <- db_detect_all(data)
  blinded <- blind_data(data, seed = 1)
  table <- db_describe_table(blinded, specs)

  expect_equal(table$column, c("id", "age"))
  expect_equal(table$class, c("character", "integer"))
  expect_equal(nrow(table), 2L)
})

# Printing ---------------------------------------------------------------

test_that("the printed summary lists the columns and the leak result", {
  lines <- format(attr(blind_data(mtcars, seed = 1), "blind_summary"))
  expect_true(any(grepl("^  mpg +numeric +numeric, synthetic values$", lines)))
  expect_true(any(grepl("^  cyl +numeric +discrete numbers, same values$", lines)))
  expect_true(any(grepl("^Rows: 32$", lines)))
  expect_true(any(grepl("^Leak check: passed$", lines)))
})

test_that("the output path is shown when there is one", {
  summary <- db_summary(
    tables = list(data = data.frame(
      column = "a", class = "numeric", note = "n", stringsAsFactors = FALSE
    )),
    leak = list(passed = TRUE, leaked = character(), matches = integer()),
    output = "/tmp/x_blinded.csv"
  )
  expect_equal(format(summary)[[1L]], "Blinded copy written to /tmp/x_blinded.csv")
})

test_that("numeric coincidences are reported only when there are some", {
  none <- db_summary(
    tables = list(data = data.frame(
      column = "a", class = "numeric", note = "n", stringsAsFactors = FALSE
    )),
    leak = list(passed = TRUE, leaked = character(), matches = c(a = 0L))
  )
  expect_false(any(grepl("coincidences", format(none))))

  some <- none
  some$leak$matches <- c(a = 12L)
  expect_true(any(grepl("^Exact numeric or date coincidences: 12", format(some))))
})

test_that("a workbook's summary names each sheet", {
  path <- tmp_path("two_sheets_for_summary.xlsx")
  file.copy(test_path("fixtures", "two_sheets.xlsx"), path, overwrite = TRUE)
  lines <- format(blind_file(path, seed = 1))

  expect_true(any(grepl("^Sheet \"patients\":$", lines)))
  expect_true(any(grepl("^Sheet \"visits\":$", lines)))
  expect_true(any(grepl("^Sheet \"empty\":$", lines)))
  expect_true(any(grepl("\\(no columns\\)", lines)))
  expect_true(any(grepl("^Rows: patients 3, visits 3, empty 0$", lines)))
})

test_that("printing returns the summary invisibly and prints the lines", {
  summary <- attr(blind_data(mtcars, seed = 1), "blind_summary")
  expect_output(print(summary), "Leak check: passed")
  expect_invisible(print(summary))
})

test_that("no real value reaches the summary of a file with real-looking data", {
  data <- data.frame(
    town = rep(c("Nimes", "Zurich"), times = 20L),
    code = rep(c("75011", "13006"), times = 20L),
    stringsAsFactors = FALSE
  )
  lines <- format(attr(blind_data(data, seed = 1), "blind_summary"))
  expect_false(any(grepl("Nimes|Zurich|75011|13006", lines)))
})
