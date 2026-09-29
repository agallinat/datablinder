# All values below are invented.

clinic <- function(n = 40L) {
  data.frame(
    patient_id = sprintf("P-%06d", seq_len(n)),
    age = as.integer(20L + seq_len(n) %% 60L),
    score = round(seq(1.5, 20.5, length.out = n), 2L),
    am = rep(c(0, 1), length.out = n),
    region = factor(rep(c("north", "south", "east"), length.out = n)),
    seen = rep(c(TRUE, FALSE, TRUE, TRUE), length.out = n),
    visit = as.Date("2021-01-01") + seq_len(n),
    postcode = rep(c("75011", "13006", "69002", "31000"), length.out = n),
    notes = paste("a handwritten note number", seq_len(n), "about the visit"),
    stringsAsFactors = FALSE
  )
}

# Shape ------------------------------------------------------------------

test_that("the blinded frame has the same columns, classes and row count", {
  real <- clinic()
  blinded <- blind_data(real, seed = 1)

  expect_named(blinded, names(real))
  expect_equal(col_classes(blinded), col_classes(real))
  expect_equal(nrow(blinded), nrow(real))
  expect_s3_class(blinded, "data.frame")
})

test_that("rows says how many rows to make", {
  real <- clinic()
  expect_equal(nrow(blind_data(real, rows = 7L, seed = 1)), 7L)
  expect_equal(nrow(blind_data(real, rows = 500L, seed = 1)), 500L)
  expect_equal(col_classes(blind_data(real, rows = 500L, seed = 1)), col_classes(real))
})

test_that("the row count is the input's by default, not thirty", {
  # FakeDataR's default is 30 rows whatever went in
  expect_equal(nrow(blind_data(clinic(7L), seed = 1)), 7L)
  expect_equal(nrow(blind_data(clinic(113L), seed = 1)), 113L)
})

test_that("the column order is kept", {
  real <- clinic()[, c("notes", "age", "patient_id")]
  expect_named(blind_data(real, seed = 1), c("notes", "age", "patient_id"))
})

test_that("duplicated column names survive", {
  real <- data.frame(a = 1:20, b = 21:40)
  names(real) <- c("x", "x")
  expect_named(blind_data(real, seed = 1), c("x", "x"))
})

test_that("a tibble comes back a tibble, a data.table a data.table", {
  skip_if_not_installed("tibble")
  blinded <- blind_data(tibble::as_tibble(clinic()), seed = 1)
  expect_s3_class(blinded, "tbl_df")

  blinded <- blind_data(data.table::as.data.table(clinic()), seed = 1)
  expect_s3_class(blinded, "data.table")
  # a data.table built by hand out of a plain list would have no self reference,
  # and would warn the first time a column was added to it
  expect_false(is.null(attr(blinded, ".internal.selfref")))
})

# Values -----------------------------------------------------------------

test_that("no real text value appears anywhere in the blinded frame", {
  real <- clinic()
  blinded <- blind_data(real, seed = 1)
  for (column in c("patient_id", "postcode", "notes")) {
    expect_length(intersect(blinded[[column]], real[[column]]), 0L)
  }
  expect_length(intersect(levels(blinded$region), levels(real$region)), 0L)
})

test_that("mtcars keeps every class and the discrete columns keep their values", {
  blinded <- blind_data(mtcars, seed = 1)
  expect_equal(col_classes(blinded), col_classes(mtcars))
  for (column in c("cyl", "vs", "am", "gear", "carb")) {
    expect_setequal(unique(blinded[[column]]), unique(mtcars[[column]]))
  }
})

test_that("the share of missing values is kept per column", {
  real <- clinic()
  real$age[1:8] <- NA
  real$notes[1:4] <- NA
  blinded <- blind_data(real, seed = 1)
  expect_equal(sum(is.na(blinded$age)), 8L)
  expect_equal(sum(is.na(blinded$notes)), 4L)
  expect_equal(sum(is.na(blinded$score)), 0L)
})

test_that("blanking rows does not cost a discrete column one of its values", {
  # two in five rows missing, spread so that the real column still holds all
  # four values
  real <- data.frame(carb = rep(c(1, 2, 3, 6), times = 25L))
  real$carb[seq(1L, 100L, by = 5L)] <- NA
  real$carb[seq(2L, 100L, by = 5L)] <- NA
  expect_setequal(unique(db_present(real$carb)), c(1, 2, 3, 6))

  blinded <- blind_data(real, seed = 1)
  expect_setequal(unique(db_present(blinded$carb)), c(1, 2, 3, 6))
  expect_equal(sum(is.na(blinded$carb)), 40L)
})

# Options ----------------------------------------------------------------

test_that("blind_names renames the columns and keeps their order", {
  blinded <- blind_data(clinic(), blind_names = TRUE, seed = 1)
  expect_named(blinded, sprintf("col_%02d", 1:9))
  expect_equal(unname(col_classes(blinded)), unname(col_classes(clinic())))
})

test_that("blind_names pads the numbers to the widest one", {
  expect_equal(db_blinded_names(3L), c("col_01", "col_02", "col_03"))
  expect_equal(db_blinded_names(100L)[[1L]], "col_001")
  expect_equal(db_blinded_names(0L), character())
})

test_that("blind_names drops variable labels", {
  real <- clinic()
  attr(real$age, "label") <- "Age at the first visit"
  expect_null(attr(blind_data(real, blind_names = TRUE, seed = 1)[[2L]], "label"))
  expect_equal(
    attr(blind_data(real, seed = 1)$age, "label"),
    "Age at the first visit"
  )
})

test_that("keep_labels keeps factor levels and category values", {
  real <- clinic()
  blinded <- blind_data(real, keep_labels = TRUE, seed = 1)
  expect_equal(levels(blinded$region), levels(real$region))
})

test_that("the same seed gives an identical frame", {
  real <- clinic()
  expect_identical(blind_data(real, seed = 5), blind_data(real, seed = 5))
  expect_false(identical(blind_data(real, seed = 5), blind_data(real, seed = 6)))
})

test_that("blinding leaves the session's RNG state alone", {
  set.seed(31)
  runif(1)
  before <- .Random.seed
  blind_data(clinic(), seed = 1)
  blind_data(clinic(), seed = NULL)
  expect_identical(.Random.seed, before)
})

# The summary attribute --------------------------------------------------

test_that("the summary is attached and describes every column", {
  blinded <- blind_data(clinic(), seed = 1)
  summary <- attr(blinded, "blind_summary")

  expect_s3_class(summary, "blind_summary")
  expect_equal(summary$tables$data$column, names(clinic()))
  expect_equal(summary$rows, 40L)
  expect_true(summary$leak$passed)
})

# Bad arguments ----------------------------------------------------------

test_that("a non data frame is refused", {
  expect_error(blind_data(1:10), "must be a data frame")
  expect_error(blind_data(list(a = 1)), "must be a data frame")
})

test_that("the flags must be TRUE or FALSE", {
  expect_error(blind_data(clinic(), blind_names = "yes"), "`blind_names`")
  expect_error(blind_data(clinic(), keep_labels = NA), "`keep_labels`")
  expect_error(blind_data(clinic(), blind_names = c(TRUE, TRUE)), "`blind_names`")
})

test_that("rows must be a whole number of one or more", {
  expect_error(blind_data(clinic(), rows = 0L), "`rows`")
  expect_error(blind_data(clinic(), rows = -5L), "`rows`")
  expect_error(blind_data(clinic(), rows = 2.5), "`rows`")
  expect_error(blind_data(clinic(), rows = "many"), "`rows`")
})

test_that("a column of an unsupported type is refused by name", {
  real <- data.frame(ok = 1:5)
  real$odd <- complex(real = 1:5, imaginary = 5:1)
  expect_error(blind_data(real), "\"odd\"")
})

# Edge cases -------------------------------------------------------------

test_that("an all-missing column stays all missing", {
  real <- data.frame(a = 1:20, b = rep(NA_character_, 20L))
  blinded <- blind_data(real, seed = 1)
  expect_true(all(is.na(blinded$b)))
  expect_type(blinded$b, "character")
})

test_that("a one-row frame works", {
  blinded <- blind_data(clinic(1L), seed = 1)
  expect_equal(nrow(blinded), 1L)
  expect_equal(col_classes(blinded), col_classes(clinic(1L)))
})

test_that("a frame with no rows works", {
  real <- clinic()[0L, ]
  blinded <- blind_data(real, seed = 1)
  expect_equal(nrow(blinded), 0L)
  expect_named(blinded, names(real))
})

test_that("accented and non-ASCII text is handled", {
  real <- data.frame(
    ville = rep(c("Nimes", "Zurich", "Koln"), times = 10L),
    stringsAsFactors = FALSE
  )
  real$ville <- rep(c("Nîmes", "Zürich", "Köln"), times = 10L)
  blinded <- blind_data(real, seed = 1)
  expect_type(blinded$ville, "character")
  expect_length(intersect(blinded$ville, real$ville), 0L)
})

# The one success criterion ----------------------------------------------

test_that("an analysis written for the blinded data runs on the real data", {
  real <- clinic(200L)
  blinded <- blind_data(real, seed = 1)

  # written looking only at `blinded`
  analyse <- function(data) {
    kept <- data[!is.na(data$score) & data$score > 5, ]
    by_region <- tapply(kept$score, kept$region, mean)
    counts <- table(data$region, data$am)
    model <- stats::lm(score ~ age + am, data = data)
    list(
      by_region = by_region,
      counts = counts,
      coefficients = stats::coef(model),
      ids = length(unique(data$patient_id)),
      widths = unique(nchar(data$postcode)),
      year = unique(format(data$visit, "%Y"))
    )
  }

  on_blinded <- analyse(blinded)
  expect_no_error(on_real <- analyse(real))

  # The results are structurally the same, which is the criterion in SPEC.md
  # section 1. The group *names* differ on purpose: the levels were relabelled
  # A, B, C, which is what keep_labels = TRUE is for.
  expect_equal(length(on_blinded$by_region), length(on_real$by_region))
  expect_equal(dim(on_blinded$counts), dim(on_real$counts))
  expect_equal(names(on_blinded$coefficients), names(on_real$coefficients))
  expect_equal(on_blinded$widths, on_real$widths)
  expect_equal(on_blinded$ids, on_real$ids)
})

test_that("keep_labels makes the group names match too", {
  real <- clinic(200L)
  blinded <- blind_data(real, keep_labels = TRUE, seed = 1)
  by_region <- function(data) names(tapply(data$score, data$region, mean))
  expect_equal(by_region(blinded), by_region(real))
})

# keep_real --------------------------------------------------------------

test_that("a column named by keep_real comes through untouched", {
  real <- clinic()
  blinded <- blind_data(real, keep_real = "region", seed = 1)

  expect_equal(blinded$region, real$region)
  expect_equal(levels(blinded$region), levels(real$region))
  # and the rest is still blinded
  expect_false(identical(blinded$patient_id, real$patient_id))
  expect_false(identical(blinded$notes, real$notes))
})

test_that("keep_real takes several columns and leaves the others alone", {
  real <- clinic()
  blinded <- blind_data(real, keep_real = c("region", "visit", "am"), seed = 1)

  for (column in c("region", "visit", "am")) {
    expect_equal(blinded[[column]], real[[column]], info = column)
  }
  for (column in c("patient_id", "age", "score", "seen", "postcode", "notes")) {
    expect_false(identical(blinded[[column]], real[[column]]), info = column)
  }
})

test_that("keeping a column changes neither the shape nor the classes", {
  real <- clinic()
  blinded <- blind_data(real, keep_real = "visit", seed = 1)

  expect_named(blinded, names(real))
  expect_equal(col_classes(blinded), col_classes(real))
  expect_equal(nrow(blinded), nrow(real))
})

test_that("nothing is kept by default", {
  real <- clinic()
  for (value in list(NULL, character())) {
    blinded <- blind_data(real, keep_real = value, seed = 1)
    expect_false(identical(blinded$region, real$region))
    expect_equal(attr(blinded, "blind_summary")$leak$kept, character())
  }
})

test_that("a kept column keeps its real name under blind_names", {
  real <- clinic()
  blinded <- blind_data(real, keep_real = "region", blind_names = TRUE, seed = 1)

  # The numbering stays positional, so a column can still be traced back to the
  # one it came from.
  expect_named(blinded, c(
    "col_01", "col_02", "col_03", "col_04", "region",
    "col_06", "col_07", "col_08", "col_09"
  ))
  expect_equal(blinded$region, real$region)
})

test_that("a kept column keeps its variable label under blind_names", {
  real <- data.frame(arm = c("a", "b", "a", "b"), score = c(1.5, 2.5, 3.5, 4.5))
  attr(real$arm, "label") <- "Treatment arm"
  attr(real$score, "label") <- "Baseline score"

  blinded <- blind_data(real, keep_real = "arm", blind_names = TRUE, seed = 1)
  expect_equal(attr(blinded$arm, "label"), "Treatment arm")
  expect_null(attr(blinded$col_02, "label"))
})

test_that("keep_real and rows cannot be used together", {
  expect_error(
    blind_data(clinic(), keep_real = "region", rows = 10L),
    "cannot be used together"
  )
})

test_that("keep_real must name columns the data has, and says which it cannot", {
  expect_error(
    blind_data(clinic(), keep_real = "arm"),
    "does not have: \"arm\"",
    fixed = TRUE
  )
  expect_error(
    blind_data(clinic(), keep_real = c("region", "arm", "site")),
    "columns that the data does not have: \"arm\", \"site\"",
    fixed = TRUE
  )
})

test_that("keep_real must be a character vector of names", {
  for (value in list(1, TRUE, NA_character_, c("region", NA), c("region", ""))) {
    expect_error(
      blind_data(clinic(), keep_real = value),
      "must be a character vector of column names"
    )
  }
})

test_that("naming the same column twice is the same as naming it once", {
  real <- clinic()
  blinded <- blind_data(real, keep_real = c("region", "region"), seed = 1)

  expect_equal(blinded$region, real$region)
  expect_equal(attr(blinded, "blind_summary")$leak$kept, "region")
})

test_that("keeping every column returns the data as it was", {
  real <- clinic(5L)
  blinded <- blind_data(real, keep_real = names(real), seed = 1)
  attr(blinded, "blind_summary") <- NULL
  expect_equal(as.data.frame(blinded), real)
})

test_that("the summary names the kept column and the leak check still passes", {
  real <- clinic()
  info <- attr(blind_data(real, keep_real = c("region", "visit"), seed = 1),
    "blind_summary"
  )
  lines <- format(info)

  expect_true(info$leak$passed)
  expect_equal(info$leak$kept, c("region", "visit"))
  expect_match(
    lines[grepl("^Leak check", lines)],
    "passed, except 2 columns kept real: region, visit",
    fixed = TRUE
  )
  expect_match(
    lines[grepl("^  region", lines)], "REAL VALUES KEPT, not blinded",
    fixed = TRUE
  )
})

test_that("a kept column is not counted as a coincidence", {
  # score is continuous, so left to itself it is counted, not forbidden; kept, it
  # should not be counted either, or every row would look like a coincidence.
  info <- attr(blind_data(clinic(), keep_real = "score", seed = 1),
    "blind_summary"
  )
  expect_false("score" %in% names(info$leak$matches))
})

test_that("keeping an identifier does not trip the leak check", {
  # The one case the check would otherwise stop: identifiers are forbidden from
  # overlapping at all.
  real <- clinic()
  blinded <- blind_data(real, keep_real = "patient_id", seed = 1)

  expect_equal(blinded$patient_id, real$patient_id)
  expect_true(attr(blinded, "blind_summary")$leak$passed)
})

test_that("a kept column stays lined up with its own rows", {
  real <- clinic(60L)
  blinded <- blind_data(real, keep_real = c("region", "visit"), seed = 1)
  expect_equal(
    tapply(blinded$visit, blinded$region, min),
    tapply(real$visit, real$region, min)
  )
})

test_that("keep_real works on a tibble and a data.table", {
  skip_if_not_installed("tibble")
  real <- clinic(20L)

  blinded <- blind_data(tibble::as_tibble(real), keep_real = "region", seed = 1)
  expect_s3_class(blinded, "tbl_df")
  expect_equal(blinded$region, real$region)

  blinded <- blind_data(data.table::as.data.table(real),
    keep_real = "region", seed = 1
  )
  expect_s3_class(blinded, "data.table")
  expect_equal(blinded$region, real$region)
})

test_that("keeping a column does not disturb the session's RNG", {
  set.seed(99L)
  before <- .Random.seed
  blind_data(clinic(), keep_real = "region", seed = 1)
  expect_equal(.Random.seed, before)
})
