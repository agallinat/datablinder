# Builds the demo file used for the README screenshot.
#
# Every value here is invented. The columns are chosen to show one of each
# interesting detected type in the app's summary: an identifier, text dates, a
# continuous measure, two categories, a 0/1 flag and an email address.
#
# Run from the package root:  Rscript data-raw/make_screenshot_data.R
# Then run datablinder::run_app(), upload the file it wrote, press Blind and
# save the screenshot as man/figures/app.png.

set.seed(42)
n <- 40

patients <- data.frame(
  patient_id = sprintf("P-%06d", sample(100000:999999, n)),
  visit_date = format(as.Date("2023-01-05") + sample(0:300, n), "%d/%m/%Y"),
  age = sample(21:88, n, replace = TRUE),
  sex = sample(c("F", "M"), n, replace = TRUE),
  region = sample(c("North", "South", "East"), n, replace = TRUE),
  treated = sample(c(0L, 1L), n, replace = TRUE),
  weight_kg = round(stats::rnorm(n, 74, 12), 1),
  email = paste0("contact", seq_len(n), "@clinic.example"),
  stringsAsFactors = FALSE
)
# A share of missing values for the app to keep.
patients$weight_kg[c(3, 17)] <- NA

file <- "data-raw/patients_demo.csv"
utils::write.csv(patients, file, row.names = FALSE, na = "")
message("Wrote ", file, ". Upload it in run_app() for the screenshot.")
