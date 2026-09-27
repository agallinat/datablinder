# Builds the test fixtures in tests/testthat/fixtures.
#
# Every value here is invented. Numbers are chosen so that reading and writing
# them back gives the same text (no trailing zeros, no rounding), which lets
# the round-trip tests compare files byte for byte.
#
# Run from the package root:  Rscript data-raw/make_fixtures.R

dir <- "tests/testthat/fixtures"
dir.create(dir, recursive = TRUE, showWarnings = FALSE)

write_bytes <- function(lines, file, eol = "\n", encoding = "UTF-8",
                        bom = FALSE) {
  text <- paste0(paste(lines, collapse = eol), eol)
  bytes <- if (encoding == "UTF-8") {
    charToRaw(enc2utf8(text))
  } else {
    iconv(text, from = "UTF-8", to = encoding, toRaw = TRUE)[[1]]
  }
  if (bom) {
    bytes <- c(as.raw(c(0xef, 0xbb, 0xbf)), bytes)
  }
  con <- file(file.path(dir, file), open = "wb")
  on.exit(close(con))
  writeBin(bytes, con)
}

# Comma separated, dot decimal, blank for missing, UTF-8, LF endings.
write_bytes(c(
  "id,age,score,sex,visit_date,notes",
  "P-000001,34,12.5,M,2021-03-04,first visit",
  "P-000002,,9.75,F,2021-03-05,",
  "P-000003,51,10.2,M,2021-04-11,follow up",
  "P-000004,29,8.4,F,,missing date"
), "comma.csv")

# Semicolon separated, comma decimal, "NA" for missing (a European export).
write_bytes(c(
  "id;age;score;sex",
  "P-000001;34;12,5;M",
  "P-000002;NA;9,75;F",
  "P-000003;51;10,2;NA"
), "semicolon.csv")

# Tab separated.
write_bytes(c(
  "id\tage\tscore",
  "P-000001\t34\t12.5",
  "P-000002\t41\t9.75"
), "tabs.tsv")

# Latin-1, with accented text and CRLF endings.
write_bytes(
  c(
    "id,ville,note",
    "P-000001,Nîmes,très bien",
    "P-000002,Réunion,assez bien"
  ),
  "latin1.csv",
  eol = "\r\n", encoding = "latin1"
)

# UTF-8 with a byte order mark, as written by Excel.
write_bytes(c(
  "id,ville",
  "P-000001,Nîmes",
  "P-000002,Zürich"
), "bom.csv", eol = "\r\n", bom = TRUE)

# Two sheets with different columns, plus an empty third sheet.
writexl::write_xlsx(
  list(
    patients = data.frame(
      id = c("P-000001", "P-000002", "P-000003"),
      age = c(34L, NA, 51L),
      score = c(12.5, 9.75, 10.2),
      sex = c("M", "F", "M"),
      stringsAsFactors = FALSE
    ),
    visits = data.frame(
      id = c("P-000001", "P-000001", "P-000002"),
      visit = c(1L, 2L, 1L),
      seen = c(TRUE, TRUE, FALSE),
      stringsAsFactors = FALSE
    ),
    empty = data.frame()
  ),
  path = file.path(dir, "two_sheets.xlsx")
)

# SPSS and Stata, with value labels, variable labels and a date column. `consent`
# declares 99 as user-missing: write_sav() cannot store that declaration, so the
# .sav ends up with a missing value and a value label for a code that never
# appears, while the .dta keeps the 99 as an ordinary value. Both are worth
# having.
labelled <- data.frame(
  patient_id = sprintf("P-%06d", 1:6),
  stringsAsFactors = FALSE
)
labelled$age <- structure(c(34, 51, 29, 46, 38, 61), label = "Age in years")
labelled$sex <- haven::labelled(
  c(1, 2, 1, 2, 1, 2), c(Male = 1, Female = 2),
  label = "Sex of the patient"
)
labelled$score <- structure(
  c(12.5, 9.75, 10.2, 8.4, 11.1, 7.25),
  label = "Score at entry"
)
labelled$visit_date <- as.Date(c(
  "2021-03-04", "2021-03-05", "2021-04-11", "2021-05-02", "2021-05-30",
  "2021-06-14"
))
labelled$region <- haven::labelled(
  c(1, 2, 3, 1, 2, 3), c(North = 1, South = 2, East = 3),
  label = "Region of residence"
)
labelled$consent <- haven::labelled_spss(
  c(1, 1, 2, 99, 1, 2), c(Yes = 1, No = 2, Refused = 99),
  na_values = 99, label = "Consent given"
)

haven::write_sav(labelled, file.path(dir, "labelled.sav"))
haven::write_dta(labelled, file.path(dir, "labelled.dta"))

# An R object: a plain data frame with a factor, an ordered factor and a logical.
saveRDS(
  data.frame(
    patient_id = sprintf("P-%06d", 1:6),
    arm = factor(
      c("control", "treatment", "control", "treatment", "control", "treatment"),
      levels = c("control", "treatment")
    ),
    grade = factor(
      c("low", "high", "medium", "low", "high", "medium"),
      levels = c("low", "medium", "high"), ordered = TRUE
    ),
    weight = c(62.4, 80.1, 71.6, 55.9, 90.3, 68.8),
    seen = c(TRUE, TRUE, FALSE, TRUE, FALSE, TRUE),
    stringsAsFactors = FALSE
  ),
  file.path(dir, "table.rds")
)

message("Fixtures written to ", dir)
