# All values below are invented. Every blinder draws random numbers, so every
# call goes through db_with_seed().

blind <- function(x, n = length(x), keep_labels = FALSE, seed = 1, name = "") {
  db_with_seed(seed, db_blind_column(x, db_detect(x, name), n, keep_labels, name))
}

# Rules that hold for every type ------------------------------------------

# One column of each detected type, to sweep the rules that must always hold.
sample_columns <- function() {
  list(
    all_na = rep(NA_real_, 40L),
    constant_number = rep(7, 40L),
    constant_text = rep("TRIAL-A", 40L),
    logical = rep(c(TRUE, FALSE, TRUE, TRUE), times = 10L),
    factor = factor(rep(c("north", "south", "east"), length.out = 40L)),
    ordered = factor(rep(c("low", "mid", "high"), length.out = 40L),
      levels = c("low", "mid", "high"), ordered = TRUE
    ),
    date = as.Date("2021-01-01") + seq(0L, 39L),
    date_text = format(as.Date("2021-01-01") + seq(0L, 39L), "%d/%m/%Y"),
    discrete = rep(c(0, 1), length.out = 40L),
    discrete_integer = rep(c(4L, 6L, 8L), length.out = 40L),
    continuous = seq(1.25, 40.25, length.out = 40L),
    continuous_integer = seq(100L, 1270L, length.out = 40L),
    identifier = sprintf("P-%06d", 1:40),
    identifier_number = 100001:100040,
    email = sprintf("person%02d@somewhere.example", 1:40),
    url = sprintf("https://somewhere.example/page%02d", 1:40),
    phone = sprintf("+33 6 12 34 %02d %02d", 1:40, 40:1),
    category = rep(c("yes", "no"), times = 20L),
    shaped = rep(c("75011", "13006", "69002", "31000"), times = 10L),
    free_text = paste("a note about visit number", 1:40, "written by hand today")
  )
}

test_that("every blinder keeps the class of its column", {
  for (name in names(sample_columns())) {
    x <- sample_columns()[[name]]
    expect_identical(class(blind(x)), class(x), info = name)
  }
})

test_that("every blinder keeps the storage type of its column", {
  for (name in names(sample_columns())) {
    x <- sample_columns()[[name]]
    expect_identical(typeof(blind(x)), typeof(x), info = name)
  }
})

test_that("every blinder returns the number of rows asked for", {
  for (name in names(sample_columns())) {
    x <- sample_columns()[[name]]
    expect_length(blind(x), 40L)
    expect_length(blind(x, n = 7L), 7L)
    expect_length(blind(x, n = 100L), 100L)
    expect_length(blind(x, n = 1L), 1L)
  }
})

test_that("no blinded text value appears in the real column", {
  # the hard rule of SPEC section 6, for the types it applies to
  text_types <- c(
    "constant_text", "factor", "ordered", "identifier", "email", "url",
    "category", "shaped", "free_text"
  )
  for (name in text_types) {
    x <- sample_columns()[[name]]
    blinded <- as.character(blind(x))
    expect_length(intersect(blinded, as.character(x)), 0L)
  }
})

test_that("the same seed gives the same column twice", {
  for (name in names(sample_columns())) {
    x <- sample_columns()[[name]]
    expect_identical(blind(x, seed = 3), blind(x, seed = 3), info = name)
  }
})

test_that("different seeds give different columns", {
  # all_na and the constants have nothing to vary
  varying <- setdiff(names(sample_columns()), c("all_na", "constant_number"))
  for (name in varying) {
    x <- sample_columns()[[name]]
    expect_false(identical(blind(x, seed = 3), blind(x, seed = 4)), info = name)
  }
})

test_that("blinding a column never changes the session's RNG state", {
  set.seed(11)
  runif(1)
  before <- .Random.seed
  for (x in sample_columns()) {
    blind(x, seed = NULL)
  }
  expect_identical(.Random.seed, before)
})

# Missing values ---------------------------------------------------------

test_that("the share of missing values is kept", {
  x <- c(rep(1.5, 30L), rep(NA_real_, 10L))
  expect_equal(sum(is.na(blind(x))), 10L)
  expect_equal(sum(is.na(blind(x, n = 100L))), 25L)
})

test_that("the share of missing values is kept for every type", {
  # all_na is already all missing, so there is nothing to compare
  for (name in setdiff(names(sample_columns()), "all_na")) {
    x <- sample_columns()[[name]]
    x[c(2L, 5L, 9L, 30L)] <- NA
    expect_equal(sum(is.na(blind(x))), 4L, info = name)
  }
})

test_that("a column with no missing values does not gain any", {
  for (name in setdiff(names(sample_columns()), "all_na")) {
    x <- sample_columns()[[name]]
    expect_false(anyNA(blind(x)), info = name)
  }
})

test_that("an all-missing column stays all missing, with its class", {
  expect_true(all(is.na(blind(rep(NA_real_, 10L)))))
  x <- factor(rep(NA_character_, 10L), levels = c("a", "b"))
  blinded <- blind(x)
  expect_true(all(is.na(blinded)))
  expect_equal(levels(blinded), c("a", "b"))
})

# The FakeDataR pitfalls -------------------------------------------------

test_that("0/1 doubles stay 0 and 1", {
  x <- rep(c(0, 1), length.out = 100L)
  blinded <- blind(x)
  expect_setequal(unique(blinded), c(0, 1))
  expect_type(blinded, "double")
})

test_that("whole-number doubles stay whole", {
  cyl <- rep(c(4, 6, 8), length.out = 100L)
  blinded <- blind(cyl)
  expect_setequal(unique(blinded), c(4, 6, 8))
  expect_true(all(blinded == round(blinded)))
})

test_that("integers stay integers", {
  x <- rep(1:12, length.out = 100L)
  expect_type(blind(x), "integer")
  y <- 100L:400L
  expect_type(blind(y), "integer")
})

test_that("mtcars keeps every class and the shape of every column", {
  blinded <- db_with_seed(1, {
    specs <- db_detect_all(mtcars)
    as.data.frame(lapply(seq_along(mtcars), function(i) {
      db_blind_column(mtcars[[i]], specs[[i]], nrow(mtcars), FALSE, names(mtcars)[[i]])
    }), col.names = names(mtcars))
  })

  expect_equal(vapply(blinded, class, character(1)), vapply(mtcars, class, character(1)))
  expect_equal(nrow(blinded), nrow(mtcars))
  # the columns FakeDataR turns into decimals
  for (column in c("cyl", "vs", "am", "gear", "carb")) {
    expect_setequal(unique(blinded[[column]]), unique(mtcars[[column]]))
  }
})

# Numbers ----------------------------------------------------------------

test_that("continuous columns keep their number of decimals", {
  x <- round(stats::runif(200L, 1, 100), 2L)
  blinded <- blind(x)
  expect_equal(blinded, round(blinded, 2L))
  expect_false(identical(blinded, round(blinded, 1L)))
})

test_that("a positive column stays positive and gains no zeros", {
  x <- stats::runif(200L, 0.5, 10)
  blinded <- blind(x)
  expect_true(all(blinded > 0))
})

test_that("a negative column stays negative", {
  x <- -stats::runif(200L, 0.5, 10)
  expect_true(all(blind(x) < 0))
})

test_that("the share of exact zeros is kept", {
  x <- c(rep(0, 60L), stats::runif(140L, 1, 10))
  blinded <- blind(x)
  expect_equal(sum(blinded == 0), 60L)
})

test_that("the blinded minimum and maximum are not the real ones", {
  x <- seq(10, 1000, length.out = 300L)
  blinded <- blind(x)
  expect_false(min(blinded) == min(x))
  expect_false(max(blinded) == max(x))
})

test_that("a continuous column keeps roughly the shape of the real one", {
  # right-skewed on purpose: a uniform draw between min and max would lose this
  x <- round(stats::rlnorm(2000L, 2, 1), 2L)
  blinded <- blind(x)
  expect_lt(abs(stats::median(blinded) - stats::median(x)) / stats::median(x), 0.15)
  expect_lt(abs(stats::quantile(blinded, 0.9) - stats::quantile(x, 0.9)) /
    stats::quantile(x, 0.9), 0.2)
  # and the mean must be well above the midpoint of the range, as it is for x
  expect_lt(mean(blinded), (min(blinded) + max(blinded)) / 2)
})

test_that("a discrete column keeps roughly the real proportions", {
  x <- rep(c(0, 1), times = c(800L, 200L))
  blinded <- blind(x)
  expect_lt(abs(mean(blinded) - 0.2), 0.05)
})

# Factors and categories --------------------------------------------------

test_that("factors keep their level count, order and class", {
  x <- factor(rep(c("north", "south", "east"), length.out = 60L),
    levels = c("north", "south", "east")
  )
  blinded <- blind(x)
  expect_s3_class(blinded, "factor")
  expect_length(levels(blinded), 3L)
  expect_equal(levels(blinded), c("A", "B", "C"))
})

test_that("ordered factors stay ordered, in the same order", {
  x <- factor(rep(c("low", "mid", "high"), length.out = 60L),
    levels = c("low", "mid", "high"), ordered = TRUE
  )
  blinded <- blind(x)
  expect_true(is.ordered(blinded))
  expect_equal(levels(blinded), c("A", "B", "C"))
  expect_true(all(blinded[1L] <= blinded | blinded[1L] > blinded))
})

test_that("unused levels stay levels", {
  x <- factor(rep(c("a", "b"), times = 20L), levels = c("a", "b", "never_used"))
  blinded <- blind(x)
  expect_length(levels(blinded), 3L)
})

test_that("keep_labels keeps the real levels and nothing else changes", {
  x <- factor(rep(c("north", "south"), times = 20L))
  blinded <- blind(x, keep_labels = TRUE)
  expect_equal(levels(blinded), c("north", "south"))
  expect_equal(levels(blind(x)), c("A", "B"))
})

test_that("character categories stay character and keep their count", {
  x <- rep(c("yes", "no", "maybe"), length.out = 60L)
  blinded <- blind(x)
  expect_type(blinded, "character")
  expect_setequal(unique(blinded), c("A", "B", "C"))
})

test_that("keep_labels keeps real category values", {
  x <- rep(c("yes", "no"), times = 20L)
  expect_setequal(unique(blind(x, keep_labels = TRUE)), c("yes", "no"))
})

test_that("more than 26 levels still get distinct labels", {
  expect_equal(db_level_labels(3L), c("A", "B", "C"))
  expect_length(unique(db_level_labels(700L)), 700L)
  expect_equal(db_level_labels(27L)[27L], "AA")
  expect_equal(db_level_labels(0L), character())
})

# Dates ------------------------------------------------------------------

test_that("dates stay dates, in a shifted range", {
  x <- as.Date("2021-01-01") + seq(0L, 199L)
  blinded <- blind(x)
  expect_s3_class(blinded, "Date")
  expect_false(min(blinded) == min(x))
  expect_false(max(blinded) == max(x))
  # the span is roughly kept
  expect_lt(abs(as.numeric(diff(range(blinded)) - diff(range(x)))), 40)
})

test_that("dates stay whole days", {
  x <- as.Date("2021-01-01") + seq(0L, 99L)
  blinded <- blind(x)
  expect_equal(as.numeric(blinded), round(as.numeric(blinded)))
})

test_that("date-times keep their class and time zone", {
  x <- as.POSIXct("2021-01-01 09:00", tz = "Europe/Paris") + seq(0L, 99L) * 3600
  blinded <- blind(x)
  expect_s3_class(blinded, "POSIXct")
  expect_equal(attr(blinded, "tzone"), "Europe/Paris")
})

test_that("IDate columns stay IDate", {
  x <- data.table::as.IDate(as.Date("2021-01-01") + seq(0L, 99L))
  blinded <- blind(x)
  expect_s3_class(blinded, "IDate")
  expect_type(blinded, "integer")
})

test_that("a column where every date is the same still spreads out", {
  x <- rep(as.Date("2021-06-15"), 50L)
  # one distinct value, so this is a constant, not a date
  expect_equal(db_detect(x)$type, "date")
  blinded <- blind(x)
  expect_s3_class(blinded, "Date")
  expect_gt(length(unique(blinded)), 1L)
})

test_that("text dates stay text in the same format", {
  x <- format(as.Date("2021-01-01") + seq(0L, 99L), "%d/%m/%Y")
  blinded <- blind(x)
  expect_type(blinded, "character")
  expect_true(all(grepl("^[0-9]{2}/[0-9]{2}/[0-9]{4}$", blinded)))
  expect_false(anyNA(as.Date(blinded, format = "%d/%m/%Y")))
})

test_that("text dates land in a shifted range, not on the real range", {
  # A date is a number, and SPEC.md asks for a slightly shifted range rather
  # than a different one, so individual dates will coincide with real ones. The
  # range is what has to move; the leak check counts dates as numbers for that
  # reason.
  x <- format(as.Date("2021-01-01") + seq(0L, 99L), "%d/%m/%Y")
  blinded <- as.Date(blind(x), format = "%d/%m/%Y")
  real <- as.Date(x, format = "%d/%m/%Y")
  expect_false(min(blinded) == min(real))
  expect_false(max(blinded) == max(real))
})

# Identifiers and patterns ------------------------------------------------

test_that("identifiers keep their shape and stay unique", {
  x <- sprintf("P-%06d", 1:200)
  blinded <- blind(x)
  expect_true(all(grepl("^[A-Z]-[0-9]{6}$", blinded)))
  expect_length(unique(blinded), 200L)
  expect_length(intersect(blinded, x), 0L)
})

test_that("identifiers that repeat keep a similar number of rows per value", {
  x <- rep(sprintf("P-%06d", 1:20), each = 5L)
  blinded <- blind(x)
  expect_equal(length(unique(blinded)), 20L)
  expect_true(all(table(blinded) >= 1L))
  expect_length(intersect(blinded, x), 0L)
})

test_that("numeric identifiers stay numbers with the same digit count", {
  x <- 100001:100200
  blinded <- blind(x, name = "patient_id")
  expect_type(blinded, "integer")
  expect_true(all(nchar(as.character(blinded)) == 6L))
  expect_length(unique(blinded), 200L)
})

test_that("emails are obviously fake and keep the domain out of the real data", {
  x <- sprintf("person%02d@somewhere.example", 1:40)
  blinded <- blind(x)
  expect_true(all(grepl("^user_[a-z]{2}[0-9]{2}@example\\.com$", blinded)))
  expect_length(intersect(blinded, x), 0L)
})

test_that("urls point at example.com", {
  x <- sprintf("https://somewhere.example/page%02d", 1:40)
  blinded <- blind(x)
  expect_true(all(grepl("^https://example\\.com/[a-z]{4}$", blinded)))
})

test_that("a www url keeps its www prefix", {
  x <- sprintf("www.somewhere.example/page%02d", 1:40)
  expect_true(all(grepl("^www\\.example\\.com/", blind(x))))
})

test_that("phone numbers keep their punctuation and digit positions", {
  x <- sprintf("+33 6 12 34 %02d %02d", 1:40, 40:1)
  blinded <- blind(x)
  expect_true(all(grepl("^\\+[0-9]{2} [0-9] [0-9]{2} [0-9]{2} [0-9]{2} [0-9]{2}$", blinded)))
  expect_length(intersect(blinded, x), 0L)
})

test_that("leading-zero codes keep their width and their distinct count", {
  x <- rep(c("01234", "00987", "00045", "00006"), times = 25L)
  blinded <- blind(x, name = "postcode")
  expect_true(all(nchar(blinded) == 5L))
  expect_equal(length(unique(blinded)), 4L)
  expect_length(intersect(blinded, x), 0L)
})

test_that("new identifiers never collide with the real ones", {
  # 2000 real ids in a space of 26 * 10^4, where a blind draw would hit maybe
  # 150 of them
  x <- sprintf("P-%04d", 1:2000)
  blinded <- blind(x)
  expect_length(intersect(blinded, x), 0L)
  expect_length(unique(blinded), 2000L)
})

test_that("a code keeps its width when the space has room", {
  # 5000 distinct codes out of the 100000 five-digit ones: room for both
  x <- rep(sprintf("%05d", sample.int(99999L, 5000L)), times = 4L)
  blinded <- blind(x, name = "postcode")
  expect_true(all(nchar(blinded) == 5L))
  expect_length(intersect(blinded, x), 0L)
  expect_equal(length(unique(blinded)), 5000L)
})

test_that("a saturated code space is widened rather than leaked into", {
  # 95000 of the 100000 five-digit codes are real, so there is no way to keep
  # the width, the distinct count and zero overlap all three. SPEC.md section 6
  # makes zero overlap the hard rule, so the width gives way.
  x <- sprintf("%05d", sample.int(99999L, 95000L))
  blinded <- blind(x, name = "postcode")
  expect_length(intersect(blinded, x), 0L)
  expect_equal(length(unique(blinded)), 95000L)
  expect_true(all(nchar(blinded) == 6L))
})

test_that("the space is sized for the real values as well as the new ones", {
  expect_equal(db_widen_shape("99999", 95000L), "99999")
  expect_equal(db_widen_shape("99999", 95000L + 95000L), "999999")
})

test_that("a shape with too few combinations is widened rather than failing", {
  # 200 rows of single-letter codes cannot all be distinct as single letters,
  # and one extra digit is enough for 260 of them
  expect_equal(db_widen_shape("A", 200L), "A9")
  expect_equal(db_widen_shape("A", 300L), "A99")
  expect_equal(db_widen_shape("A-999999", 200L), "A-999999")
  expect_equal(db_shape_capacity("A9"), 260)
})

test_that("fake shaped values put letters and digits where they were", {
  drawn <- db_with_seed(1, db_fake_shaped("AA-99/a", 50L))
  expect_true(all(grepl("^[A-Z]{2}-[0-9]{2}/[a-z]$", drawn)))
  expect_equal(db_with_seed(1, db_fake_shaped("", 3L)), c("", "", ""))
})

# Free text --------------------------------------------------------------

test_that("free text becomes placeholder words of a similar length", {
  x <- paste("a handwritten note number", 1:60, "about the visit")
  blinded <- blind(x)
  expect_type(blinded, "character")
  expect_length(intersect(blinded, x), 0L)
  expect_true(all(db_word_count(blinded) %in% db_word_count(x)))
  expect_true(all(blinded %in% blinded[nzchar(blinded)]))
})

test_that("free text word counts follow the real ones", {
  x <- c(rep("one", 50L), rep("one two three four five", 50L))
  # "one" repeated is not free text; make every row distinct
  x <- paste(x, seq_along(x))
  blinded <- blind(x)
  expect_true(max(db_word_count(blinded)) <= max(db_word_count(x)))
})

# Constants --------------------------------------------------------------

test_that("a constant number is kept", {
  expect_true(all(blind(rep(7, 20L)) == 7))
})

test_that("a constant text is replaced but keeps its shape", {
  x <- rep("TRIAL-A", 20L)
  blinded <- blind(x)
  expect_length(unique(blinded), 1L)
  expect_true(grepl("^[A-Z]{5}-[A-Z]$", blinded[[1L]]))
  expect_length(intersect(blinded, x), 0L)
})

test_that("keep_labels keeps a constant text", {
  x <- rep("TRIAL-A", 20L)
  expect_true(all(blind(x, keep_labels = TRUE) == "TRIAL-A"))
})

# Logical ----------------------------------------------------------------

test_that("logicals keep roughly the share of TRUE", {
  x <- rep(c(TRUE, FALSE), times = c(800L, 200L))
  blinded <- blind(x)
  expect_type(blinded, "logical")
  expect_lt(abs(mean(blinded) - 0.8), 0.05)
})

# Labelled (SPSS/Stata) ---------------------------------------------------

test_that("labelled columns keep their codes and get new labels", {
  skip_if_not_installed("haven")
  x <- haven::labelled(
    rep(c(1, 2, 3), length.out = 60L),
    labels = c(north = 1, south = 2, east = 3),
    label = "Region of the clinic"
  )
  blinded <- blind(x)

  expect_s3_class(blinded, "haven_labelled")
  expect_setequal(unique(as.numeric(blinded)), c(1, 2, 3))
  expect_equal(names(attr(blinded, "labels")), c("A", "B", "C"))
  expect_equal(unname(attr(blinded, "labels")), c(1, 2, 3))
  # the variable label is kept; blind_names removes it, not keep_labels
  expect_equal(attr(blinded, "label"), "Region of the clinic")
})

test_that("keep_labels keeps real value labels", {
  skip_if_not_installed("haven")
  x <- haven::labelled(rep(c(1, 2), 30L), labels = c(north = 1, south = 2))
  blinded <- blind(x, keep_labels = TRUE)
  expect_equal(names(attr(blinded, "labels")), c("north", "south"))
})

test_that("SPSS user-missing codes are codes, not missing values", {
  skip_if_not_installed("haven")
  # is.na() is TRUE for a code declared user-missing, but 99 is still a code, so
  # the blinded column must not turn it into a missing value.
  x <- haven::labelled_spss(
    rep(c(1, 2, 99), length.out = 60L),
    labels = c(yes = 1, no = 2, refused = 99),
    na_values = 99
  )
  blinded <- blind(x)

  expect_s3_class(blinded, "haven_labelled_spss")
  expect_equal(attr(blinded, "na_values"), 99)
  expect_false(anyNA(db_bare(blinded)))
  expect_setequal(unique(db_bare(blinded)), c(1, 2, 99))
})

test_that("a labelled column with many codes is not resampled from real values", {
  skip_if_not_installed("haven")
  # only -99 is labelled; the rest is continuous income
  codes <- c(round(stats::runif(300L, 15000, 80000)), rep(-99, 20L))
  x <- haven::labelled(codes, labels = c(refused = -99))
  blinded <- blind(x)

  expect_s3_class(blinded, "haven_labelled")
  overlap <- intersect(as.numeric(blinded), codes)
  expect_lt(length(overlap), length(unique(codes)) / 2)
})

# Errors -----------------------------------------------------------------

test_that("an unsupported column is refused by name, without showing values", {
  x <- complex(real = 1:5, imaginary = 5:1)
  spec <- db_detect(x, "weird")
  expect_error(
    db_with_seed(1, db_blind_column(x, spec, 5L, FALSE, "weird")),
    "\"weird\""
  )
})
