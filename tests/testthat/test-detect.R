# All values below are invented.

detected <- function(x, name = "") {
  db_detect(x, name)$type
}

# Class-based types ------------------------------------------------------

test_that("an all-missing column is recognised whatever its class", {
  expect_equal(detected(rep(NA, 5)), "all_na")
  expect_equal(detected(rep(NA_character_, 5)), "all_na")
  expect_equal(detected(rep(NA_real_, 5)), "all_na")
  expect_equal(detected(as.Date(rep(NA, 5))), "all_na")
  expect_equal(detected(factor(rep(NA, 5), levels = c("a", "b"))), "all_na")
})

test_that("factors and ordered factors are factors", {
  expect_equal(detected(factor(c("a", "b", "a"))), "factor")
  expect_equal(detected(factor(c("low", "high"), ordered = TRUE)), "factor")
  # even with a single level, so that the level is relabelled rather than kept
  expect_equal(detected(factor(c("only", "only"))), "factor")
})

test_that("dates and date-times are dates", {
  expect_equal(detected(as.Date(c("2021-03-04", "2021-05-06"))), "date")
  expect_equal(
    detected(as.POSIXct(c("2021-03-04 10:00", "2021-05-06 11:00"), tz = "UTC")),
    "date"
  )
  # fread returns IDate, which inherits from Date
  expect_equal(detected(data.table::as.IDate(c("2021-03-04", "2021-05-06"))), "date")
})

test_that("logicals are logical, even when all the same", {
  expect_equal(detected(c(TRUE, FALSE, TRUE)), "logical")
  expect_equal(detected(c(TRUE, TRUE, TRUE)), "logical")
})

test_that("haven_labelled columns are recognised", {
  skip_if_not_installed("haven")
  x <- haven::labelled(c(1, 2, 1), labels = c(No = 1, Yes = 2))
  expect_equal(detected(x), "labelled")
})

test_that("an unsupported column type is reported rather than guessed at", {
  expect_equal(detected(complex(real = 1:3, imaginary = 1:3)), "unsupported")
  expect_equal(detected(as.raw(1:3)), "unsupported")
})

# Constants --------------------------------------------------------------

test_that("a column with one distinct value is constant", {
  expect_equal(detected(c(3, 3, 3)), "constant")
  expect_equal(detected(c("TRIAL-A", "TRIAL-A", NA)), "constant")
})

# Numbers ----------------------------------------------------------------

test_that("0/1 doubles are discrete, not continuous", {
  # the FakeDataR pitfall: am = 0.24 instead of 0 or 1
  expect_equal(detected(c(0, 1, 1, 0, 1)), "numeric_discrete")
  expect_equal(detected(c(0L, 1L, 1L, 0L)), "numeric_discrete")
})

test_that("whole-number doubles with few distinct values are discrete", {
  # the other FakeDataR pitfall: cyl = 5.07 instead of 4, 6 or 8
  cyl <- c(6, 6, 4, 6, 8, 6, 8, 4, 4, 6)
  expect_equal(detected(cyl), "numeric_discrete")
  expect_equal(detected(1:15), "numeric_discrete")
})

test_that("the discrete threshold is where the constant says it is", {
  distinct <- function(n) rep(seq_len(n), each = 3L)
  expect_equal(detected(distinct(DB_MAX_DISCRETE_VALUES)), "numeric_discrete")
  expect_equal(detected(distinct(DB_MAX_DISCRETE_VALUES + 1L)), "numeric_continuous")
})

test_that("numbers with decimals are continuous", {
  expect_equal(detected(c(1.5, 2.25, 3.75, 1.5)), "numeric_continuous")
  # whole numbers with many distinct values are continuous too
  expect_equal(detected(seq(100L, 400L, by = 10L)), "numeric_continuous")
})

test_that("a named column of unique whole numbers is an identifier", {
  expect_equal(detected(1001:1030, name = "patient_id"), "identifier")
})

test_that("a large column of unique whole numbers is an identifier unnamed", {
  n <- DB_NUMERIC_IDENTIFIER_MIN_ROWS
  expect_equal(detected(seq_len(n) + 5000L), "identifier")
  # just below the bar there is no way to tell a key from a measurement
  expect_equal(detected(seq_len(n - 1L) + 5000L), "numeric_continuous")
})

test_that("a measurement that happens to be all distinct is not an identifier", {
  # 20 different ages in 20 rows is ordinary; blinding them as IDs would ruin
  # mean(), range() and any plot
  ages <- c(34L, 51L, 29L, 44L, 61L, 38L, 22L, 47L, 55L, 30L,
            41L, 26L, 59L, 36L, 48L, 33L, 62L, 28L, 45L, 39L)
  expect_equal(detected(ages, name = "age"), "numeric_continuous")
})

test_that("a coded grouping variable is not turned into an identifier", {
  # the name says id, but 1..5 repeated is a discrete variable and code will
  # compare it with ==
  expect_equal(detected(rep(1:5, times = 20L), name = "region_id"), "numeric_discrete")
})

test_that("a numeric identifier must be whole", {
  expect_equal(detected(seq(0.5, 30.5, by = 1), name = "patient_id"), "numeric_continuous")
})

# Text patterns ----------------------------------------------------------

test_that("emails are recognised", {
  x <- c("a.b@example.com", "c@mail.example.org", "d_e@sub.example.co.uk")
  expect_equal(detected(x), "email")
})

test_that("urls are recognised", {
  x <- c("https://example.com/a", "http://example.org", "www.example.net/b")
  expect_equal(detected(x), "url")
})

test_that("phone numbers are recognised", {
  x <- c("+33 6 12 34 56 78", "06 98 76 54 32", "(020) 7946 0018")
  expect_equal(detected(x), "phone")
})

test_that("a short numeric code is not mistaken for a phone number", {
  x <- c("12345678", "87654321", "11223344", "99887766")
  expect_false(detected(x) == "phone")
})

test_that("text dates are recognised with their format", {
  spec <- db_detect(c("04/03/2021", "15/11/2020", "01/01/2019"))
  expect_equal(spec$type, "date_text")
  expect_equal(spec$format, "%d/%m/%Y")

  spec <- db_detect(c("2021-03-04", "2020-11-15", "2019-01-01"))
  expect_equal(spec$type, "date_text")
  expect_equal(spec$format, "%Y-%m-%d")
})

test_that("text dates are tested before phone numbers", {
  # "04/03/2021" passes the phone test too, so the order matters
  expect_equal(detected(c("04/03/2021", "15/11/2020", "23/07/2018")), "date_text")
  expect_equal(detected(c("2021-03-04", "2020-11-15", "2018-07-23")), "date_text")
})

test_that("a format that only half parses is not accepted", {
  # as.Date() would happily parse these with %Y-%m-%d and drop the time
  x <- c("2021-03-04 09:00", "2020-11-15 14:30", "2019-01-01 08:15")
  expect_false(detected(x) == "date_text")
})

test_that("day-first and month-first are told apart where possible", {
  expect_equal(db_text_date_format(c("15/11/2020", "23/07/2018")), "%d/%m/%Y")
  expect_equal(db_text_date_format(c("11/15/2020", "07/23/2018")), "%m/%d/%Y")
})

# Text categories, identifiers and prose ---------------------------------

test_that("character columns with few distinct values are categories", {
  expect_equal(detected(rep(c("M", "F"), times = 20L)), "category_text")
  expect_equal(detected(rep(c("North", "South", "East"), times = 10L)), "category_text")
})

test_that("the category threshold is where the constant says it is", {
  levels <- function(n) rep(paste0("level", seq_len(n)), each = 4L)
  expect_equal(detected(levels(DB_MAX_CATEGORY_VALUES)), "category_text")
  expect_false(detected(levels(DB_MAX_CATEGORY_VALUES + 1L)) == "category_text")
})

test_that("a low-cardinality column with a sensitive name stays a category", {
  # otherwise every row would get its own new town and the 4 groups would be lost
  towns <- rep(c("Alpha", "Beta", "Gamma", "Delta"), times = 25L)
  expect_equal(detected(towns, name = "city"), "category_text")
})

test_that("mostly unique short codes are identifiers", {
  x <- sprintf("P-%06d", 1:40)
  expect_equal(detected(x), "identifier")
})

test_that("a sensitive name makes an identifier out of a short column", {
  x <- c("P-000001", "P-000002", "P-000003")
  expect_equal(detected(x, name = "patient_id"), "identifier")
  # the same values without the name are too few rows to call an identifier,
  # but the shape is still worth keeping
  expect_equal(detected(x), "shaped_text")
})

test_that("an identifier that repeats is still an identifier", {
  # long format: one row per visit, so patient_id repeats
  x <- rep(c("P-000001", "P-000002", "P-000003"), times = c(3L, 1L, 2L))
  expect_equal(detected(x, name = "patient_id"), "identifier")
  expect_equal(detected(x, name = "id"), "identifier")
})

test_that("a two-value column is a category even in a two-row table", {
  # M and F in two rows must not come out as free text
  expect_equal(detected(c("M", "F")), "category_text")
  expect_equal(detected(c("M", "F", NA)), "category_text")
})

test_that("wordy category labels are categories, not free text", {
  x <- rep(c(
    "strongly agree with the statement",
    "neither agree nor disagree",
    "strongly disagree with the statement"
  ), times = 40L)
  expect_equal(detected(x), "category_text")
})

test_that("the two name lists are told apart", {
  expect_true(db_name_is_identifier("patient_id"))
  expect_false(db_name_is_identifier("city"))
  expect_true(db_name_is_sensitive("city"))
  expect_true(db_name_is_sensitive("patient_id"))
})

test_that("the sensitive-name test reads the words of a name", {
  expect_true(db_name_is_sensitive("patient_id"))
  expect_true(db_name_is_sensitive("patientID"))
  expect_true(db_name_is_sensitive("Patient.Id"))
  expect_true(db_name_is_sensitive("e mail"))
  expect_false(db_name_is_sensitive("score"))
  expect_false(db_name_is_sensitive("valid"))
  expect_false(db_name_is_sensitive("recipient"))
  expect_false(db_name_is_sensitive(""))
})

test_that("unique prose is free text, not an identifier", {
  x <- paste("the visit went", c(
    "well and the patient was discharged",
    "badly and a second appointment was made",
    "as expected with no further action needed",
    "quickly with a short review afterwards",
    "slowly but the outcome was acceptable",
    "without incident and notes were filed",
    "under supervision of the duty registrar",
    "after a delay caused by transport",
    "with a translator present throughout",
    "and follow up was arranged by phone",
    "much better than the previous one",
    "with some difficulty reported later"
  ))
  expect_equal(detected(x, name = "patient_notes"), "free_text")
})

test_that("fixed-shape text is recognised", {
  x <- paste0("AB", sprintf("%05d", 1:40), "XY")
  # all distinct, so this is an identifier; repeat it to break the uniqueness
  expect_equal(detected(c(x, x)), "shaped_text")
})

test_that("plain words of equal length are a category, not a code", {
  # "Aaaaa" is a word; keeping its shape would gain nothing and the four groups
  # matter more
  x <- rep(c("Alpha", "Gamma", "Delta", "Omega"), times = 25L)
  expect_equal(detected(x), "category_text")
})

test_that("two-letter codes are a category, not a code shape", {
  x <- rep(c("FR", "DE", "US", "GB"), times = 25L)
  expect_equal(detected(x), "category_text")
})

test_that("a shaped code wins over the category rule", {
  # five distinct postcodes in a hundred rows: code may still take a substring
  # or count characters, so the shape has to survive
  x <- rep(c("75011", "13006", "69002", "31000", "44200"), times = 20L)
  expect_equal(detected(x), "shaped_text")
})

test_that("leading-zero codes keep their shape", {
  x <- rep(sprintf("%05d", c(1234, 987, 45, 6, 77)), times = 10L)
  expect_equal(db_shape(x[1]), "99999")
  expect_equal(detected(x, name = "postcode"), "shaped_text")
})

test_that("variable-length text with many values is free text", {
  set.seed(1)
  x <- vapply(
    1:60,
    function(i) paste(rep("word", i %% 7 + 1), collapse = " "),
    character(1)
  )
  expect_equal(detected(paste(x, seq_along(x))), "free_text")
})

# Helpers ----------------------------------------------------------------

test_that("whole numbers are told from decimals exactly", {
  expect_true(db_all_whole(c(1, 2, 3)))
  expect_true(db_all_whole(c(-4, 0, 7)))
  expect_false(db_all_whole(c(1, 2.5)))
  expect_false(db_all_whole(c(1, 1 + 1e-9)))
  # infinities are ignored rather than making the test fail
  expect_true(db_all_whole(c(1, 2, Inf)))
})

test_that("the sample used for pattern tests never touches the RNG", {
  set.seed(42)
  before <- .Random.seed
  db_detect(sprintf("P-%06d", 1:(DB_DETECT_SAMPLE * 2L)), "patient_id")
  expect_identical(.Random.seed, before)
})

test_that("a large column is still sampled down to the limit", {
  values <- as.character(seq_len(DB_DETECT_SAMPLE * 3L))
  expect_lte(length(db_even_sample(values)), DB_DETECT_SAMPLE)
  expect_equal(length(db_even_sample(values[1:10])), 10L)
})

test_that("non-ASCII text is handled without error", {
  x <- rep(c("Nîmes", "Zürich", "Köln"), times = 10L)
  expect_equal(detected(x), "category_text")
  expect_equal(db_shape("Nîmes"), "Aaaaa")
})

# Whole data frames ------------------------------------------------------

test_that("every column of a data frame gets a spec, in order", {
  data <- data.frame(
    patient_id = sprintf("P-%06d", 1:20),
    age = c(34L, 51L, 29L, 44L, 61L, 38L, 22L, 47L, 55L, 30L,
            41L, 26L, 59L, 36L, 48L, 33L, 62L, 28L, 45L, 39L),
    am = rep(c(0, 1), times = 10L),
    sex = factor(rep(c("M", "F"), times = 10L)),
    score = seq(1.5, 11.0, length.out = 20L),
    visit = rep(as.Date("2021-03-04") + 0:4, times = 4L),
    empty = rep(NA, 20L),
    stringsAsFactors = FALSE
  )
  specs <- db_detect_all(data)

  expect_named(specs, names(data))
  expect_equal(
    vapply(specs, function(spec) spec$type, character(1), USE.NAMES = FALSE),
    c("identifier", "numeric_continuous", "numeric_discrete", "factor",
      "numeric_continuous", "date", "all_na")
  )
})

test_that("a one-row data frame makes every column constant", {
  # worth pinning down: with one row nothing can be told apart
  data <- data.frame(a = 1, b = "x", stringsAsFactors = FALSE)
  types <- vapply(db_detect_all(data), function(spec) spec$type, character(1))
  expect_equal(unname(types), c("constant", "constant"))
})
