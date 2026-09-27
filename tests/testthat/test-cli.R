# All values below are invented.

# A private copy of a fixture, so that the blinded file lands in the temp
# directory and not next to the fixtures.
staged_cli <- function(fixture) {
  path <- tmp_path(paste0("cli_", fixture))
  file.copy(test_path("fixtures", fixture), path, overwrite = TRUE)
  path
}

# The exit status and both streams, with nothing left on the test's own output.
run_cli <- function(...) {
  status <- NULL
  err <- NULL
  out <- capture.output(
    err <- capture.output(status <- db_cli(c(...)), type = "message")
  )
  list(status = status, out = out, err = err)
}

# Parsing ----------------------------------------------------------------

test_that("a bare file name gives the defaults", {
  parsed <- db_cli_parse("patients.csv")

  expect_equal(parsed$path, "patients.csv")
  expect_null(parsed$output)
  expect_false(parsed$blind_names)
  expect_false(parsed$keep_labels)
  expect_null(parsed$rows)
  expect_null(parsed$seed)
})

test_that("the four options and the output path are read", {
  parsed <- db_cli_parse(c(
    "patients.csv", "--blind-names", "--keep-labels",
    "--rows", "200", "--seed", "42", "--output", "fake.csv"
  ))

  expect_true(parsed$blind_names)
  expect_true(parsed$keep_labels)
  expect_equal(parsed$rows, 200)
  expect_equal(parsed$seed, 42)
  expect_equal(parsed$output, "fake.csv")
})

test_that("options may be written with an equals sign, and -o is --output", {
  parsed <- db_cli_parse(c("--rows=200", "-o", "fake.csv", "patients.csv"))

  expect_equal(parsed$rows, 200)
  expect_equal(parsed$output, "fake.csv")
  expect_equal(parsed$path, "patients.csv")
})

test_that("a negative seed is a seed, not an option", {
  expect_equal(db_cli_parse(c("patients.csv", "--seed", "-1"))$seed, -1)
})

test_that("help and version need no file", {
  expect_true(db_cli_parse("--help")$help)
  expect_true(db_cli_parse("-h")$help)
  expect_true(db_cli_parse("--version")$version)
  expect_true(db_cli_parse("-V")$version)
})

test_that("bad arguments are refused", {
  expect_error(db_cli_parse(character()), "No input file")
  expect_error(db_cli_parse("--rows"), "needs a value")
  expect_error(db_cli_parse(c("patients.csv", "--rows", "many")), "whole number")
  expect_error(db_cli_parse(c("patients.csv", "--wrong")), "Unknown option")
  expect_error(db_cli_parse(c("a.csv", "b.csv")), "one file")
})

# Messages ---------------------------------------------------------------

test_that("--help prints the usage and succeeds", {
  result <- run_cli("--help")

  expect_equal(result$status, 0L)
  expect_match(result$out[[1]], "^Usage: datablinder")
  expect_true(any(grepl("not a formal", result$out, fixed = TRUE)))
})

test_that("--version prints the package version", {
  result <- run_cli("--version")

  expect_equal(result$status, 0L)
  expect_equal(
    result$out, paste("datablinder", utils::packageVersion("datablinder"))
  )
})

test_that("a bad argument explains itself on stderr and fails", {
  result <- run_cli("--wrong")

  expect_equal(result$status, 1L)
  expect_match(result$err[[1]], "Unknown option")
  expect_match(result$err[[2]], "--help", fixed = TRUE)
})

test_that("a missing file fails without printing a summary", {
  result <- run_cli(tmp_path("not_here.csv"))
  expect_equal(result$status, 1L)
  expect_match(result$err[[1]], "File not found")

  expect_equal(run_cli(tmp_path("not_here.csv"))$out, character())
})

# Blinding ---------------------------------------------------------------

test_that("a file is blinded and the summary printed", {
  path <- staged_cli("comma.csv")
  result <- run_cli(path, "--seed", "1")

  expect_equal(result$status, 0L)
  expect_match(result$out[[1]], "Blinded copy written to", fixed = TRUE)
  expect_true(any(grepl("Leak check: passed", result$out, fixed = TRUE)))
  expect_true(file.exists(sub("\\.csv$", "_blinded.csv", path)))
})

test_that("the options reach blind_file()", {
  path <- staged_cli("comma.csv")
  output <- tmp_path("cli_chosen.csv")
  result <- run_cli(
    path, "--output", output, "--blind-names", "--rows", "7", "--seed", "42"
  )

  expect_equal(result$status, 0L)
  blinded <- db_read(output)$tables$data
  expect_equal(nrow(blinded), 7L)
  expect_true(all(grepl("^col_[0-9]+$", names(blinded))))
})

test_that("the same seed gives the same file twice", {
  path <- staged_cli("comma.csv")
  first <- tmp_path("cli_first.csv")
  second <- tmp_path("cli_second.csv")

  run_cli(path, "-o", first, "--seed", "3")
  run_cli(path, "-o", second, "--seed", "3")

  expect_equal(file_bytes(first), file_bytes(second))
})

test_that("a failed leak check fails the command and writes nothing", {
  path <- staged_cli("comma.csv")
  output <- tmp_path("cli_leaked.csv")
  unlink(output)
  local_mocked_bindings(
    db_check_leak_tables = function(...) {
      list(passed = FALSE, leaked = "a", matches = integer())
    }
  )

  result <- run_cli(path, "-o", output, "--seed", "1")

  expect_equal(result$status, 1L)
  expect_match(result$err[[1]], "Leak check failed")
  expect_false(file.exists(output))
})

# The script -----------------------------------------------------------

test_that("the shipped script is executable R that calls db_cli()", {
  script <- system.file("scripts", "datablinder", package = "datablinder")
  skip_if(script == "", "script not installed")

  expect_no_error(parse(script))
  expect_true(any(grepl("db_cli", readLines(script), fixed = TRUE)))

  # Windows has no execute bit to check, which is the whole reason install_cli()
  # writes a .cmd shim there.
  skip_on_os("windows")
  expect_equal(file.access(script, mode = 1L)[[1]], 0L)
})

test_that("the wrapper leaves the session's RNG alone", {
  path <- staged_cli("comma.csv")
  set.seed(99)
  before <- .Random.seed

  run_cli(path, "-o", tmp_path("cli_rng.csv"), "--seed", "1")

  expect_identical(.Random.seed, before)
})
