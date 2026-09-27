# All values below are invented.

# A fileInput value pointing at a private copy of a fixture, so that the app
# deleting the upload does not touch the fixture itself.
as_upload <- function(fixture, name = fixture) {
  dir <- tempfile("upload-")
  dir.create(dir)
  path <- file.path(dir, name)
  file.copy(test_path("fixtures", fixture), path, overwrite = TRUE)
  data.frame(
    name = name, size = file.size(path), type = "", datapath = path,
    stringsAsFactors = FALSE
  )
}

# A fileInput value for a file the package cannot read.
as_bad_upload <- function() {
  dir <- tempfile("upload-")
  dir.create(dir)
  path <- file.path(dir, "notes.docx")
  writeLines("not a data file", path)
  data.frame(
    name = "notes.docx", size = file.size(path), type = "", datapath = path,
    stringsAsFactors = FALSE
  )
}

options_for <- function(session, ..., rows = NA, seed = 1) {
  session$setInputs(
    blind_names = FALSE, keep_labels = FALSE, rows = rows, seed = seed, ...
  )
}

# The sidebar ------------------------------------------------------------

test_that("the rows and seed boxes say what they do", {
  html <- as.character(db_app_ui())

  expect_match(html, "Number of rows in the blinded copy", fixed = TRUE)
  expect_match(html, "the same seed gives the same fake values", fixed = TRUE)
  # Bootstrap's small muted style, so a hint does not shout as loud as a label.
  expect_match(html, "form-text", fixed = TRUE)
})

# Blinding a file --------------------------------------------------------

test_that("uploading a csv and pressing Blind gives a summary and a file", {
  shiny::testServer(db_app(), {
    options_for(session, file = as_upload("comma.csv"))
    session$setInputs(blind = 1)

    expect_match(output$summary, "Leak check: passed")
    expect_match(output$summary, "Rows: 4")
    # One line per column, by name.
    for (column in c("id", "age", "score", "sex", "visit_date", "notes")) {
      expect_match(output$summary, column, fixed = TRUE)
    }

    downloaded <- output$blinded_file
    expect_true(file.exists(downloaded))
    expect_named(
      db_read(downloaded)$tables$data,
      c("id", "age", "score", "sex", "visit_date", "notes")
    )
  })
})

test_that("the download is named after the input", {
  shiny::testServer(db_app(), {
    options_for(session, file = as_upload("comma.csv"))
    session$setInputs(blind = 1)
    expect_equal(basename(output$blinded_file), "comma_blinded.csv")
  })
})

test_that("the download button only appears once something has been blinded", {
  shiny::testServer(db_app(), {
    options_for(session, file = as_upload("comma.csv"))
    expect_null(output$download)

    session$setInputs(blind = 1)
    expect_match(as.character(output$download$html), "Download blinded file")
  })
})

test_that("the summary shown in the app leaves out the temporary path", {
  shiny::testServer(db_app(), {
    options_for(session, file = as_upload("comma.csv"))
    session$setInputs(blind = 1)
    expect_no_match(output$summary, "written to")
  })
})

# The options ------------------------------------------------------------

test_that("rows, blind_names and keep_labels reach blind_file()", {
  shiny::testServer(db_app(), {
    options_for(session, file = as_upload("comma.csv"), rows = 25)
    session$setInputs(blind = 1)
    expect_match(output$summary, "Rows: 25")
    expect_equal(nrow(db_read(output$blinded_file)$tables$data), 25L)

    session$setInputs(blind_names = TRUE, keep_labels = TRUE, blind = 2)
    expect_match(output$summary, "col_01")
    expect_match(output$summary, "categories kept")
  })
})

test_that("an empty rows or seed box means the input's rows and a random seed", {
  shiny::testServer(db_app(), {
    options_for(session, file = as_upload("comma.csv"), rows = NA, seed = NA)
    session$setInputs(blind = 1)
    expect_match(output$summary, "Rows: 4")
    expect_match(output$summary, "Leak check: passed")
  })
})

test_that("the seed decides the file, and the upload survives a second run", {
  shiny::testServer(db_app(), {
    options_for(session, file = as_upload("comma.csv"), seed = 1)
    session$setInputs(blind = 1)
    first <- file_bytes(output$blinded_file)

    session$setInputs(blind = 2)
    expect_equal(file_bytes(output$blinded_file), first)

    session$setInputs(seed = 2, blind = 3)
    expect_false(identical(file_bytes(output$blinded_file), first))
  })
})

# The preview ------------------------------------------------------------

test_that("the preview shows the blinded rows and no real value", {
  real <- db_read(test_path("fixtures", "comma.csv"))$tables$data
  shiny::testServer(db_app(), {
    options_for(session, file = as_upload("comma.csv"))
    session$setInputs(blind = 1)

    preview <- as.character(output$preview)
    expect_match(preview, "<table")
    expect_match(preview, "score")
    for (value in c(db_present(real$id), db_present(real$notes))) {
      expect_false(grepl(value, preview, fixed = TRUE), info = value)
    }
  })
})

test_that("a workbook gets a sheet selector and the preview follows it", {
  shiny::testServer(db_app(), {
    options_for(session, file = as_upload("two_sheets.xlsx"))
    session$setInputs(blind = 1)

    selector <- as.character(output$sheet$html)
    expect_match(selector, "patients")
    expect_match(selector, "visits")

    expect_match(as.character(output$preview), "score")
    session$setInputs(sheet = "visits")
    expect_match(as.character(output$preview), "seen")
    expect_no_match(as.character(output$preview), "score")
  })
})

test_that("a single table gets no sheet selector", {
  shiny::testServer(db_app(), {
    options_for(session, file = as_upload("comma.csv"))
    session$setInputs(blind = 1)
    expect_null(output$sheet)
  })
})

test_that("the preview is at most ten rows of text", {
  tables <- list(data = data.frame(
    n = 1:20,
    when = as.Date("2021-01-01") + 1:20,
    grade = factor(rep(c("A", "B"), 10L), levels = c("A", "B"), ordered = TRUE)
  ))
  preview <- db_app_preview(tables)

  expect_equal(nrow(preview), DB_APP_PREVIEW_ROWS)
  expect_named(preview, c("n", "when", "grade"))
  expect_true(all(vapply(preview, is.character, logical(1))))
})

test_that("the preview follows the chosen sheet and copes with an empty one", {
  tables <- list(
    first = data.frame(a = 1:3),
    second = data.frame(b = 4:6),
    empty = data.frame()
  )
  expect_named(db_app_preview(tables), "a")
  expect_named(db_app_preview(tables, "second"), "b")
  expect_named(db_app_preview(tables, "gone"), "a")
  expect_null(db_app_preview(tables, "empty"))
})

# What can go wrong ------------------------------------------------------

test_that("pressing Blind with no file changes nothing", {
  shiny::testServer(db_app(), {
    options_for(session)
    session$setInputs(blind = 1)
    expect_equal(output$summary, DB_APP_PLACEHOLDER)
    expect_null(output$download)
    expect_null(output$preview)
  })
})

test_that("a file that cannot be read leaves the app standing", {
  shiny::testServer(db_app(), {
    options_for(session, file = as_bad_upload())
    session$setInputs(blind = 1)
    expect_equal(output$summary, DB_APP_PLACEHOLDER)
    expect_null(output$download)

    # and a good file afterwards still works
    session$setInputs(file = as_upload("comma.csv"), blind = 2)
    expect_match(output$summary, "Leak check: passed")
  })
})

# Housekeeping -----------------------------------------------------------

test_that("the uploaded file is deleted once it has been blinded", {
  shiny::testServer(db_app(), {
    info <- as_upload("comma.csv")
    options_for(session, file = info)
    session$setInputs(blind = 1)
    expect_false(file.exists(info$datapath))
  })
})

test_that("two uploads with the same name do not overwrite each other", {
  dir <- tempfile("work-")
  dir.create(dir)
  first <- as_upload("comma.csv", name = "data.csv")
  second <- as_upload("semicolon.csv", name = "data.csv")

  staged_first <- db_app_stage(first, dir)
  staged_second <- db_app_stage(second, dir, staged_first)

  expect_false(identical(staged_first$path, staged_second$path))
  expect_equal(db_read(staged_first$path)$meta$sep, ",")
  expect_equal(db_read(staged_second$path)$meta$sep, ";")
})

test_that("staging reuses its copy for a second run of the same upload", {
  dir <- tempfile("work-")
  dir.create(dir)
  info <- as_upload("comma.csv")

  staged <- db_app_stage(info, dir)
  expect_false(file.exists(info$datapath))
  expect_equal(db_app_stage(info, dir, staged), staged)
})

test_that("an empty rows or seed box becomes NULL", {
  expect_null(db_app_number(NA))
  expect_null(db_app_number(NA_integer_))
  expect_null(db_app_number(NULL))
  expect_equal(db_app_number(25), 25)
})

test_that("the app is a shiny app and the RStudio addin points at run_app", {
  expect_s3_class(db_app(), "shiny.appobj")

  addins <- read.dcf(system.file("rstudio", "addins.dcf",
    package = "datablinder"
  ))
  expect_equal(unname(addins[, "Binding"]), "run_app")
  expect_true(exists("run_app", envir = asNamespace("datablinder")))
})
