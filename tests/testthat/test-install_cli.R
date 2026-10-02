# A scratch directory that is on nobody's PATH.
cli_dir <- function(name = "bin") {
  path <- tmp_path(file.path("install_cli", name))
  unlink(path, recursive = TRUE)
  path
}

# Run code with a PATH of our own, put back afterwards.
with_path <- function(dirs, code) {
  old <- Sys.getenv("PATH")
  on.exit(Sys.setenv(PATH = old), add = TRUE)
  Sys.setenv(PATH = paste(dirs, collapse = .Platform$path.sep))
  code
}

# Run code as if this were Windows.
with_windows <- function(code) {
  local_mocked_bindings(db_is_windows = function() TRUE)
  code
}

# Run code as if the scratch directory outlived the session. A test may not
# write outside tempdir(), so consent has to be exercised on a directory that
# is inside it while the package is told otherwise.
as_permanent <- function(code) {
  local_mocked_bindings(db_under_tempdir = function(dir) FALSE)
  code
}

# Run code with somebody at the console giving one answer to anything asked.
answering <- function(answer, code) {
  local_mocked_bindings(
    db_is_interactive = function() TRUE,
    db_ask_yes_no = function(question) answer
  )
  code
}

# Installing -------------------------------------------------------------

test_that("the command is copied into the directory, which is created", {
  dir <- cli_dir()
  expect_false(dir.exists(dir))

  target <- suppressMessages(install_cli(dir))

  expect_equal(target, file.path(dir, "datablinder"))
  expect_true(file.exists(target))
  expect_true(any(grepl("db_cli", readLines(target), fixed = TRUE)))
})

test_that("the installed command is executable and can be installed again", {
  skip_on_os("windows")
  dir <- cli_dir()

  target <- suppressMessages(install_cli(dir))
  expect_equal(file.access(target, mode = 1L)[[1]], 0L)

  # A second call overwrites rather than failing.
  expect_equal(suppressMessages(install_cli(dir)), target)
})

test_that("no .cmd shim is written away from Windows", {
  skip_on_os("windows")
  dir <- cli_dir()

  suppressMessages(install_cli(dir))
  expect_equal(list.files(dir), "datablinder")
})

test_that("Windows gets a shim that calls Rscript on the script beside it", {
  dir <- cli_dir()
  local_mocked_bindings(db_is_windows = function() TRUE)

  suppressMessages(install_cli(dir))
  shim <- readLines(file.path(dir, "datablinder.cmd"))

  expect_setequal(list.files(dir), c("datablinder", "datablinder.cmd"))
  expect_equal(shim[[1]], "@echo off")
  expect_match(shim[[2]], "%~dp0datablinder", fixed = TRUE)
  expect_match(shim[[2]], "Rscript")
  # Quoted, or a home directory with a space in it would break it.
  expect_match(shim[[2]], "^\"")
})

test_that("a path that is a file, not a directory, is an error", {
  file <- tmp_path("install_cli_file")
  writeLines("x", file)

  expect_error(install_cli(file), "Could not create the directory")
})

# Consent ----------------------------------------------------------------

test_that("a directory that outlives the session is written to only on a yes", {
  dir <- cli_dir()

  target <- as_permanent(answering(TRUE, suppressMessages(install_cli(dir))))

  expect_equal(target, file.path(dir, "datablinder"))
  expect_true(file.exists(target))
})

test_that("a no writes nothing at all, not even the directory", {
  dir <- cli_dir()

  expect_message(
    expect_null(as_permanent(answering(FALSE, install_cli(dir)))),
    "Nothing was written"
  )
  expect_false(dir.exists(dir))
})

test_that("the question says which directory would be written to", {
  dir <- cli_dir()
  asked <- NULL
  local_mocked_bindings(
    db_is_interactive = function() TRUE,
    db_ask_yes_no = function(question) {
      asked <<- question
      FALSE
    }
  )

  as_permanent(suppressMessages(install_cli(dir)))

  expect_match(asked, dir, fixed = TRUE)
})

test_that("with nobody to ask, writing outside tempdir() is an error", {
  dir <- cli_dir()
  local_mocked_bindings(
    db_is_interactive = function() FALSE,
    db_ask_yes_no = function(question) stop("should not have asked")
  )

  expect_error(as_permanent(install_cli(dir)), "only runs where it can ask")
  expect_false(dir.exists(dir))
})

test_that("a directory under tempdir() is written without asking", {
  dir <- cli_dir()
  local_mocked_bindings(
    db_is_interactive = function() TRUE,
    db_ask_yes_no = function(question) stop("should not have asked")
  )

  expect_true(file.exists(suppressMessages(install_cli(dir))))
})

test_that("a directory under tempdir() is recognised before it exists", {
  dir <- cli_dir("not-yet")
  expect_false(dir.exists(dir))

  expect_true(db_under_tempdir(dir))
  expect_true(db_under_tempdir(tempdir()))
  expect_false(db_under_tempdir(file.path("~", ".local", "bin")))
})

test_that("only a yes is a yes, and a bare return key is not", {
  expect_true(all(vapply(c("y", "Y", " yes "), db_is_yes, logical(1))))
  expect_false(any(vapply(c("n", "", "maybe"), db_is_yes, logical(1))))
})

# What the user is told --------------------------------------------------

test_that("a directory on the PATH is reported as ready to use", {
  dir <- cli_dir()
  dir.create(dir, recursive = TRUE)

  with_path(c(dir, "/usr/bin"), {
    expect_message(install_cli(dir), "already on your PATH")
    expect_message(install_cli(dir), "datablinder --help", fixed = TRUE)
  })
})

test_that("a directory off the PATH is reported, with the full path to use", {
  # The POSIX hint, whatever we are running on. The test below covers Windows.
  local_mocked_bindings(db_is_windows = function() FALSE)
  dir <- cli_dir()

  # capture_messages() and not capture.output(type = "message"): the notes are a
  # message() condition, and under devtools::test() those are muffled before they
  # ever reach a sink, so the sink would capture nothing and all three
  # expectations below would fail for the wrong reason.
  said <- with_path("/usr/bin", {
    capture_messages(install_cli(dir))
  })

  expect_true(any(grepl("not on your PATH", said, fixed = TRUE)))
  expect_true(any(grepl(file.path(dir, "datablinder"), said, fixed = TRUE)))
  expect_true(any(grepl("export PATH", said, fixed = TRUE)))
})

test_that("the Windows hint does not tell the user to run setx", {
  hint <- with_windows(db_cli_path_hint("C:/Users/a/bin"))

  expect_true(any(grepl("Settings", hint, fixed = TRUE)))
  expect_false(any(grepl("setx", hint, fixed = TRUE)))
})

# Choosing the directory -------------------------------------------------

test_that("the default is the first candidate that is on the PATH", {
  first <- cli_dir("first")
  second <- cli_dir("second")
  dir.create(first, recursive = TRUE)
  dir.create(second, recursive = TRUE)
  local_mocked_bindings(db_cli_dirs = function() c(first, second))

  expect_equal(with_path(c("/usr/bin", second), db_cli_dir()), second)
})

test_that("with no candidate on the PATH the first one is used", {
  first <- cli_dir("first")
  second <- cli_dir("second")
  local_mocked_bindings(db_cli_dirs = function() c(first, second))

  expect_equal(with_path("/usr/bin", db_cli_dir()), first)
})

test_that("a directory that cannot be written to is not chosen", {
  skip_on_os("windows")
  skip_if(unname(Sys.info()[["user"]]) == "root", "root can write anywhere")
  readonly <- cli_dir("readonly")
  usable <- cli_dir("usable")
  dir.create(readonly, recursive = TRUE)
  dir.create(usable, recursive = TRUE)
  Sys.chmod(readonly, "0500")
  on.exit(Sys.chmod(readonly, "0700"), add = TRUE)
  local_mocked_bindings(db_cli_dirs = function() c(readonly, usable))

  expect_equal(with_path(c(readonly, usable), db_cli_dir()), usable)
})

test_that("the Windows default sits under LOCALAPPDATA", {
  old <- Sys.getenv("LOCALAPPDATA")
  Sys.setenv(LOCALAPPDATA = "C:/Users/a/AppData/Local")
  on.exit(Sys.setenv(LOCALAPPDATA = old), add = TRUE)

  expect_equal(
    with_windows(db_cli_dirs()),
    "C:/Users/a/AppData/Local/datablinder/bin"
  )
})

# PATH comparison --------------------------------------------------------

test_that("two spellings of one directory are the same directory", {
  dir <- cli_dir()
  dir.create(dir, recursive = TRUE)

  with_path(c("/usr/bin", paste0(dir, "/")), {
    expect_true(db_on_path(dir))
    expect_false(db_on_path(cli_dir("elsewhere")))
  })
})

test_that("an empty PATH entry is not read as a directory", {
  expect_equal(
    with_path(c("/usr/bin", "", "/bin"), db_path_dirs()),
    c("/usr/bin", "/bin")
  )
})
