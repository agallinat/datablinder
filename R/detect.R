# Deciding what each column is.
#
# Types are decided by values, not only by storage class: a double holding only
# 0 and 1 is binary, and a double holding whole numbers with few distinct values
# is discrete. Getting this wrong is what breaks the one promise of the package,
# so every threshold below is a named constant and every rule has a test.
#
# This file knows nothing about file formats or about blinding.

# Thresholds ------------------------------------------------------------

# A whole-number column with no more than this many distinct values is discrete,
# so that table(), x == 1 and factor(x) keep behaving the same way.
DB_MAX_DISCRETE_VALUES <- 15L

# A character column with no more than this many distinct values is a category
# rather than free text.
DB_MAX_CATEGORY_VALUES <- 30L

# Share of non-missing values that must be distinct before a column counts as
# an identifier.
DB_IDENTIFIER_UNIQUENESS <- 0.95

# ... and, unless the column name itself looks sensitive, how many rows are
# needed before "all values differ" means anything. The bar is much higher for
# numbers, because in a small table a measurement such as age is all distinct
# by chance, while text that is all distinct is rarely a measurement.
DB_TEXT_IDENTIFIER_MIN_ROWS <- 10L
DB_NUMERIC_IDENTIFIER_MIN_ROWS <- 100L

# Share of sampled values that must match a pattern (email, URL, phone, date)
# for the whole column to be treated that way.
DB_PATTERN_SHARE <- 0.9

# Share of sampled values that must share one pattern of letters, digits and
# punctuation for the column to count as fixed-shape text, and how long that
# pattern must be. A code worth keeping the shape of also has a digit or a
# separator in it; values made only of letters are labels, not codes.
DB_SHAPE_SHARE <- 0.9
DB_MIN_SHAPE_CHARS <- 3L

# Median number of words above which text is prose rather than a code or label.
DB_PROSE_WORDS <- 3L

# How many values to look at for the pattern, shape and prose tests. Chosen by
# even spacing rather than at random, so detection never touches the RNG.
DB_DETECT_SAMPLE <- 10000L

# Text date formats, tried in this order. Day-first before month-first, as the
# ambiguous cases are more often European.
DB_DATE_FORMATS <- c(
  "%Y-%m-%d", "%Y/%m/%d", "%d/%m/%Y", "%m/%d/%Y", "%d-%m-%Y",
  "%d.%m.%Y", "%d %b %Y", "%b %d %Y", "%Y%m%d"
)

# Column names matched against the name's words, so that "patient_id" and
# "patientID" both hit "id". The idea and part of these lists come from
# FakeDataR (MIT); see inst/COPYRIGHTS for the notice its licence requires.

# Names that say "this column is a key". Enough on their own, repeats and all:
# a long-format table has one patient_id per visit, and SPEC.md asks for a
# similar number of rows per identifier.
DB_IDENTIFIER_NAME_WORDS <- c(
  "id", "ids", "identifier", "identification", "uuid", "guid", "key",
  "mrn", "ssn", "nino", "nhs", "insee", "siret", "passport", "iban",
  "accession", "barcode", "licence", "license", "plate"
)

# Names that say "this column is sensitive" without saying it is a key. These
# only lower the bar on row count, never on uniqueness: a "city" column holding
# four towns is a category, and blinding it as an identifier would take away the
# chance to keep its labels.
DB_SENSITIVE_NAME_WORDS <- c(
  "name", "names", "surname", "firstname", "lastname", "fullname",
  "patient", "subject", "participant", "person", "client", "customer",
  "email", "mail", "phone", "telephone", "tel", "mobile", "fax", "contact",
  "address", "addr", "street", "postcode", "postal", "zipcode", "zip",
  "city", "town", "account", "birth", "birthdate", "dob",
  "ip", "user", "username", "login", "nom", "prenom"
)

# Detection -------------------------------------------------------------

#' What kind of column is this?
#'
#' @param x A column.
#' @param name The column's name, used only for the sensitive-name test.
#' @return A list with `type` (one of the names in the table in SPEC.md
#'   section 5) and, for `date_text`, the `format` the dates are written in.
#' @noRd
db_detect <- function(x, name = "") {
  values <- db_present(x)

  if (length(values) == 0L) {
    return(db_spec("all_na"))
  }
  if (inherits(x, "haven_labelled")) {
    return(db_spec("labelled"))
  }
  if (is.factor(x)) {
    return(db_spec("factor"))
  }
  if (inherits(x, c("Date", "POSIXct"))) {
    return(db_spec("date"))
  }
  if (is.logical(x)) {
    return(db_spec("logical"))
  }
  if (length(unique(values)) == 1L) {
    return(db_spec("constant"))
  }
  if (is.numeric(x)) {
    return(db_detect_numeric(values, name))
  }
  if (is.character(x)) {
    return(db_detect_character(values, name))
  }
  db_spec("unsupported")
}

#' Detect the type of every column of a data frame
#'
#' @param data A data frame.
#' @return A list of specs, one per column, in column order.
#' @noRd
db_detect_all <- function(data) {
  specs <- lapply(seq_along(data), function(i) db_detect(data[[i]], names(data)[[i]]))
  names(specs) <- names(data)
  specs
}

db_spec <- function(type, format = NULL) {
  list(type = type, format = format)
}

db_detect_numeric <- function(values, name) {
  whole <- db_all_whole(values)

  if (whole && length(unique(values)) <= DB_MAX_DISCRETE_VALUES) {
    return(db_spec("numeric_discrete"))
  }
  if (whole && db_looks_like_identifier(values, name, DB_NUMERIC_IDENTIFIER_MIN_ROWS)) {
    return(db_spec("identifier"))
  }
  db_spec("numeric_continuous")
}

db_detect_character <- function(values, name) {
  sample <- db_even_sample(values)

  if (db_share(db_is_email(sample)) >= DB_PATTERN_SHARE) {
    return(db_spec("email"))
  }
  if (db_share(db_is_url(sample)) >= DB_PATTERN_SHARE) {
    return(db_spec("url"))
  }
  # Dates first: "04/03/2021" and "2021-03-04" would both pass the phone test.
  format <- db_text_date_format(sample)
  if (!is.null(format)) {
    return(db_spec("date_text", format = format))
  }
  if (db_share(db_is_phone(sample)) >= DB_PATTERN_SHARE) {
    return(db_spec("phone"))
  }
  # A sentence that never repeats is prose, and none of the rules below apply
  # to it.
  if (db_is_unique_prose(values, sample)) {
    return(db_spec("free_text"))
  }
  if (db_text_is_identifier(values, name)) {
    return(db_spec("identifier"))
  }
  # Before categories: a postcode column with five distinct codes is still a
  # code, and code written against it may well take a substring or count
  # characters.
  if (db_shape_is_fixed(sample)) {
    return(db_spec("shaped_text"))
  }
  # Few distinct values behave like a category whatever the column is called,
  # and blinding it as one keeps the category count and leaks nothing.
  if (length(unique(values)) <= DB_MAX_CATEGORY_VALUES) {
    return(db_spec("category_text"))
  }
  db_spec("free_text")
}

db_text_is_identifier <- function(values, name) {
  db_name_is_identifier(name) ||
    db_looks_like_identifier(values, name, DB_TEXT_IDENTIFIER_MIN_ROWS)
}

# Nearly all values distinct. A sensitive looking name lowers the bar on row
# count but not on uniqueness, so that a "region_id" holding 1..5 stays a
# discrete variable.
db_looks_like_identifier <- function(values, name, min_rows) {
  if (db_uniqueness(values) < DB_IDENTIFIER_UNIQUENESS) {
    return(FALSE)
  }
  db_name_is_sensitive(name) || length(values) >= min_rows
}

# Helpers ---------------------------------------------------------------

db_present <- function(x) {
  x[!is.na(x)]
}

db_share <- function(flags) {
  if (length(flags) == 0L) 0 else mean(flags)
}

db_uniqueness <- function(values) {
  if (length(values) == 0L) 0 else length(unique(values)) / length(values)
}

db_all_whole <- function(values) {
  values <- values[is.finite(values)]
  length(values) > 0L && all(values == round(values))
}

# Up to DB_DETECT_SAMPLE values, evenly spaced. Deterministic on purpose: the
# RNG belongs to the blinding step, not to detection.
db_even_sample <- function(values) {
  n <- length(values)
  if (n <= DB_DETECT_SAMPLE) {
    return(values)
  }
  values[unique(as.integer(seq(1L, n, length.out = DB_DETECT_SAMPLE)))]
}

# "patientID" -> c("patient", "id"), and so does "patient_id" and "Patient.Id".
db_name_words <- function(name) {
  if (length(name) != 1L || is.na(name) || !nzchar(name)) {
    return(character())
  }
  spaced <- gsub("([[:lower:]])([[:upper:]])", "\\1 \\2", name)
  strsplit(tolower(spaced), "[^[:alnum:]]+")[[1]]
}

db_name_is_identifier <- function(name) {
  any(db_name_words(name) %in% DB_IDENTIFIER_NAME_WORDS)
}

db_name_is_sensitive <- function(name) {
  any(db_name_words(name) %in% c(DB_IDENTIFIER_NAME_WORDS, DB_SENSITIVE_NAME_WORDS))
}

db_is_email <- function(x) {
  grepl("^[^[:space:]@]+@[^[:space:]@]+\\.[[:alpha:]]{2,}$", x)
}

db_is_url <- function(x) {
  grepl("^(https?://|ftp://|www\\.)[^[:space:]]+$", x)
}

db_is_phone <- function(x) {
  shaped <- grepl("^\\+?[0-9 ()./-]+$", x)
  digits <- nchar(gsub("[^0-9]", "", x))
  separated <- grepl("[ ()./+-]", x)
  # Bare digit strings need to be long enough to be a plausible number, so that
  # short numeric codes are not mistaken for phone numbers.
  shaped & digits >= 7L & digits <= 15L & (separated | digits >= 9L)
}

#' The format text dates are written in, or NULL
#'
#' Parsing and writing the value back must give exactly the original text, so
#' that a format which merely happens to parse (`%Y-%m-%d` against
#' "2021-03-04 09:00") is not accepted.
#' @noRd
db_text_date_format <- function(values) {
  # Cheap exit: dates contain a digit and are short.
  if (!all(grepl("[0-9]", values)) || max(nchar(values)) > 30L) {
    return(NULL)
  }
  for (format in DB_DATE_FORMATS) {
    parsed <- suppressWarnings(as.Date(values, format = format))
    matched <- !is.na(parsed) & format(parsed, format) == values
    if (db_share(matched) >= DB_PATTERN_SHARE) {
      return(format)
    }
  }
  NULL
}

# "P-004213" -> "A-999999": one token per character, by character class.
db_shape <- function(x) {
  x <- gsub("[[:digit:]]", "9", x)
  x <- gsub("[[:lower:]]", "a", x)
  gsub("[[:upper:]]", "A", x)
}

db_shape_is_fixed <- function(values) {
  shapes <- table(db_shape(values))
  if (length(shapes) == 0L) {
    return(FALSE)
  }
  common <- names(shapes)[[which.max(shapes)]]
  max(shapes) / length(values) >= DB_SHAPE_SHARE &&
    nchar(common) >= DB_MIN_SHAPE_CHARS &&
    # "99999" and "A-999999" are codes; "Aaaaa" is a word
    grepl("[^Aa]", common)
}

db_word_count <- function(x) {
  lengths(strsplit(trimws(x), "[[:space:]]+"))
}

db_is_prose <- function(values) {
  length(values) > 0L &&
    stats::median(db_word_count(values)) >= DB_PROSE_WORDS
}

# Sentences that never repeat. Repetition is what separates a wordy category
# label ("strongly agree with the statement", five times in a hundred rows) from
# a free-text note.
db_is_unique_prose <- function(values, sample) {
  db_uniqueness(values) >= DB_IDENTIFIER_UNIQUENESS && db_is_prose(sample)
}
