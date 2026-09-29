# The Shiny interface.
#
# The app is a thin wrapper: it stages the upload, calls blind_file() and shows
# what came back. No blinding logic lives here.

# How many rows of the blinded data to preview.
DB_APP_PREVIEW_ROWS <- 10L

# Shown until the first file has been blinded.
DB_APP_PLACEHOLDER <- "Choose a data file and press Blind."

db_app_ui <- function() {
  bslib::page_sidebar(
    title = "datablinder",
    sidebar = bslib::sidebar(
      width = 330,
      shiny::fileInput(
        "file", "Data file",
        accept = paste0(".", names(DB_EXTENSIONS)),
        placeholder = "CSV, Excel, SPSS, Stata, RDS, Parquet"
      ),
      shiny::checkboxInput("blind_names", "Blind column names", FALSE),
      shiny::checkboxInput("keep_labels", "Keep category labels", FALSE),
      db_app_field(
        shiny::selectizeInput(
          "keep_real", "Keep real (not blinded)",
          choices = character(), selected = NULL, multiple = TRUE,
          options = list(placeholder = "None: blind every column")
        ),
        paste(
          "These columns are shared exactly as they are, real values included.",
          "Only for columns that identify nobody, on their own or beside the",
          "others. Cannot be used with Rows."
        )
      ),
      db_app_field(
        shiny::numericInput("rows", "Rows", value = NA, min = 1, step = 1),
        "Number of rows in the blinded copy. Empty: as many as the input."
      ),
      db_app_field(
        shiny::numericInput("seed", "Seed", value = NA, step = 1),
        paste(
          "Any number, to make the copy reproducible: the same seed gives the",
          "same fake values. Empty: different values every time."
        )
      ),
      shiny::actionButton("blind", "Blind", class = "btn-primary"),
      shiny::uiOutput("download")
    ),
    bslib::card(
      bslib::card_header(
        shiny::div(
          class = "d-flex justify-content-between align-items-center",
          "Summary of the blinded data",
          db_app_copy_button()
        )
      ),
      shiny::verbatimTextOutput("summary")
    ),
    bslib::card(
      bslib::card_header(paste(
        "First", DB_APP_PREVIEW_ROWS, "rows of the blinded data"
      )),
      shiny::uiOutput("sheet"),
      shiny::tableOutput("preview")
    ),
    db_app_note(),
    db_app_copy_script()
  )
}

# An input with its explanation underneath. Both go in one element so that the
# hint stays with its box instead of floating in the sidebar's gap, and
# "form-text" is Bootstrap's own small muted style for exactly this.
db_app_field <- function(input, hint) {
  shiny::div(
    shiny::tagAppendAttributes(input, class = "mb-1"),
    shiny::div(class = "form-text mt-0", hint)
  )
}

# The Copy button and the few lines of JavaScript behind it, which read the text
# of the summary straight out of the page. No extra package needed.
db_app_copy_button <- function() {
  shiny::tags$button(
    id = "copy-summary", type = "button",
    class = "btn btn-sm btn-outline-secondary",
    "Copy"
  )
}

db_app_copy_script <- function() {
  shiny::tags$script(shiny::HTML(
    "document.addEventListener('click', function(event) {
  var button = event.target.closest('#copy-summary');
  if (!button) return;
  var summary = document.getElementById('summary');
  if (!summary || !navigator.clipboard) return;
  navigator.clipboard.writeText(summary.innerText).then(function() {
    button.textContent = 'Copied';
    setTimeout(function() { button.textContent = 'Copy'; }, 1500);
  });
});"
  ))
}

db_app_note <- function() {
  shiny::tags$p(
    class = "text-muted small",
    "datablinder replaces every value with a fake one, keeping the columns,",
    "classes and file format, so that analysis code written against the copy",
    "runs unchanged on the real data. It reduces the risk of disclosing the",
    "real values but gives no formal privacy guarantee: the column names,",
    "classes, row count and the broad shape of each column stay visible.",
    "A column listed under \"Keep real\" is not blinded at all and its real",
    "values are in the copy, so check the summary before sharing it.",
    "Everything runs on this computer; no data is sent anywhere."
  )
}
