# All values below are invented.

checked <- function(real, blinded, keep_labels = FALSE) {
  db_check_leaks(real, blinded, db_detect_all(real), keep_labels)
}

one <- function(...) {
  data.frame(..., stringsAsFactors = FALSE)
}

# Which rule applies to which type -----------------------------------------

test_that("the rule for each type is the one SPEC.md asks for", {
  rule <- function(type, numeric = FALSE, keep = FALSE) {
    db_leak_rule(type, numeric, keep)
  }
  expect_equal(rule("identifier"), DB_LEAK_FORBID)
  expect_equal(rule("email"), DB_LEAK_FORBID)
  expect_equal(rule("shaped_text"), DB_LEAK_FORBID)
  expect_equal(rule("phone"), DB_LEAK_FORBID)
  expect_equal(rule("factor"), DB_LEAK_CANONICAL)
  expect_equal(rule("category_text"), DB_LEAK_CANONICAL)
  expect_equal(rule("labelled"), DB_LEAK_CANONICAL)
  expect_equal(rule("numeric_continuous"), DB_LEAK_COUNT)
  expect_equal(rule("date"), DB_LEAK_COUNT)
  expect_equal(rule("date_text"), DB_LEAK_COUNT)
  expect_equal(rule("free_text"), DB_LEAK_COUNT)
  expect_equal(rule("numeric_discrete"), DB_LEAK_NONE)
  expect_equal(rule("logical"), DB_LEAK_NONE)
  expect_equal(rule("all_na"), DB_LEAK_NONE)
})

test_that("a constant number may be kept but a constant text may not", {
  expect_equal(db_leak_rule("constant", numeric = TRUE, FALSE), DB_LEAK_NONE)
  expect_equal(db_leak_rule("constant", numeric = FALSE, FALSE), DB_LEAK_FORBID)
})

test_that("keep_labels lifts the rule on the label types only", {
  for (type in DB_LABEL_TYPES) {
    expect_equal(db_leak_rule(type, FALSE, keep_labels = TRUE), DB_LEAK_NONE)
  }
  expect_equal(db_leak_rule("identifier", FALSE, keep_labels = TRUE), DB_LEAK_FORBID)
  expect_equal(db_leak_rule("shaped_text", FALSE, keep_labels = TRUE), DB_LEAK_FORBID)
})

# Catching a leak -----------------------------------------------------------

test_that("a real identifier left in the output is caught", {
  real <- one(patient_id = sprintf("P-%06d", 1:20))
  bad <- one(patient_id = c(real$patient_id[[1L]], sprintf("Q-%06d", 2:20)))
  report <- checked(real, bad)
  expect_false(report$passed)
  expect_equal(report$leaked, "patient_id")
})

test_that("a real code left in the output is caught", {
  real <- one(postcode = rep(c("75011", "13006", "69002"), times = 10L))
  bad <- one(postcode = rep(c("75011", "11111", "22222"), times = 10L))
  expect_false(checked(real, bad)$passed)
})

test_that("real factor levels left in the output are caught", {
  real <- one(region = factor(rep(c("north", "south"), times = 10L)))
  bad <- one(region = factor(rep(c("north", "south"), times = 10L)))
  report <- checked(real, bad)
  expect_false(report$passed)
  expect_equal(report$leaked, "region")
})

test_that("real value labels left in the output are caught", {
  skip_if_not_installed("haven")
  real <- one(region = haven::labelled(rep(c(1, 2), 10L), c(north = 1, south = 2)))
  bad <- real
  expect_false(checked(real, bad)$passed)
})

test_that("several leaking columns are all named", {
  real <- one(
    a = sprintf("P-%06d", 1:20),
    b = factor(rep(c("north", "south"), 10L)),
    ok = seq(1.5, 20.5, length.out = 20L)
  )
  expect_equal(checked(real, real)$leaked, c("a", "b"))
})

# Not a leak ----------------------------------------------------------------

test_that("a blinded table passes its own check", {
  real <- one(
    patient_id = sprintf("P-%06d", 1:40),
    age = seq(20L, 59L),
    am = rep(c(0, 1), times = 20L),
    region = factor(rep(c("north", "south", "east"), length.out = 40L)),
    postcode = rep(c("75011", "13006", "69002", "31000"), times = 10L),
    visit = as.Date("2021-01-01") + seq(0L, 39L),
    notes = paste("a handwritten note number", 1:40, "about the visit")
  )
  expect_true(checked(real, blind_data(real, seed = 1))$passed)
  expect_true(checked(real, blind_data(real, seed = 2))$passed)
})

test_that("categories named A, B, C in the real data are not a leak", {
  # the blinded labels are always A, B, C..., so seeing them tells nobody
  # anything; a check that failed here would fail on perfectly good data
  real <- one(grade = rep(c("A", "B", "C"), times = 20L))
  expect_true(checked(real, blind_data(real, seed = 1))$passed)
})

test_that("keeping labels on purpose is not a leak", {
  real <- one(region = factor(rep(c("north", "south"), times = 20L)))
  blinded <- blind_data(real, keep_labels = TRUE, seed = 1)
  expect_equal(levels(blinded$region), c("north", "south"))
  expect_true(checked(real, blinded, keep_labels = TRUE)$passed)
})

test_that("fewer rows than categories does not look like a leak", {
  real <- one(region = factor(rep(letters[1:10], times = 4L)))
  blinded <- blind_data(real, rows = 3L, seed = 1)
  expect_true(checked(real, blinded)$passed)
})

test_that("discrete values are meant to be the same and are not counted", {
  real <- one(am = rep(c(0, 1), times = 50L))
  report <- checked(real, blind_data(real, seed = 1))
  expect_true(report$passed)
  expect_length(report$matches, 0L)
})

# Counting coincidences -----------------------------------------------------

test_that("numeric coincidences are counted, not failed", {
  real <- one(score = round(seq(1, 10, length.out = 200L), 1L))
  report <- checked(real, blind_data(real, seed = 1))
  expect_true(report$passed)
  expect_named(report$matches, "score")
  expect_gt(report$matches[["score"]], 0L)
})

test_that("date coincidences are counted, not failed", {
  real <- one(visit = as.Date("2021-01-01") + seq(0L, 199L))
  report <- checked(real, blind_data(real, seed = 1))
  expect_true(report$passed)
  expect_gt(report$matches[["visit"]], 0L)
})

test_that("text dates are counted as dates, not held to zero overlap", {
  real <- one(visit = format(as.Date("2021-01-01") + seq(0L, 199L), "%d/%m/%Y"))
  expect_equal(db_detect(real$visit)$type, "date_text")
  report <- checked(real, blind_data(real, seed = 1))
  expect_true(report$passed)
  expect_named(report$matches, "visit")
})

# Errors --------------------------------------------------------------------

test_that("a failed check names the columns and shows no values", {
  leak <- list(passed = FALSE, leaked = c("patient_id", "region"), matches = integer())
  expect_error(db_stop_on_leak(leak), "\"patient_id\", \"region\"")
  expect_error(db_stop_on_leak(leak), "Nothing has been written")
  expect_error(db_stop_on_leak(leak), "columns")
})

test_that("one failed column is named in the singular", {
  leak <- list(passed = FALSE, leaked = "patient_id", matches = integer())
  expect_error(db_stop_on_leak(leak), "column \"patient_id\"")
})

test_that("a passing check says nothing", {
  expect_null(db_stop_on_leak(list(passed = TRUE, leaked = character(), matches = integer())))
})

# Whole workbooks -----------------------------------------------------------

test_that("every sheet is checked and failures are gathered", {
  real <- list(
    a = one(id = sprintf("P-%06d", 1:20)),
    b = one(score = seq(1.5, 20.5, length.out = 20L))
  )
  specs <- lapply(real, db_detect_all)
  report <- db_check_leak_tables(real, real, specs, FALSE)
  expect_false(report$passed)
  expect_equal(report$leaked, "id")
  expect_gt(report$matches[["b.score"]], 0L)
})
