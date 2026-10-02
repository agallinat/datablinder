# Putting the command line wrapper where the shell can find it.
#
# The script ships inside the installed package, in a directory no shell looks
# in. install_cli() copies it somewhere that is on the PATH and, on Windows,
# writes the .cmd shim that lets cmd.exe run an extensionless script. The part
# that matters most is the message at the end: a copy sitting in a directory
# that is not on the PATH looks installed and is not, which is the mistake this
# function exists to stop.

DB_CLI_COMMAND <- "datablinder"

# Where the command goes when the caller does not say. Computed rather than
# stored, because the Windows answer depends on the environment of the machine
# the function runs on, not the one the package was built on.
db_cli_dirs <- function() {
  if (db_is_windows()) {
    local <- Sys.getenv("LOCALAPPDATA", unset = Sys.getenv("APPDATA", unset = "~"))
    return(file.path(local, "datablinder", "bin"))
  }
  c("~/.local/bin", "~/bin", "/usr/local/bin")
}

#' Install the `datablinder` command
#'
#' Copies the command line wrapper out of the installed package and into a
#' directory the shell looks in, so that a file can be blinded with
#' `datablinder patients.csv` instead of a line of R. On Windows a `.cmd` shim
#' is written beside it, since `cmd.exe` cannot run the script itself.
#'
#' Nothing has to be installed to use the package from a terminal:
#' `Rscript -e 'datablinder::blind_file("patients.csv")'` works everywhere as
#' soon as the package does. This is for people who blind files often enough to
#' want a shorter command.
#'
#' The default `dir` is the first of `~/.local/bin`, `~/bin` and
#' `/usr/local/bin` that is already on the `PATH` and writable, or
#' `~/.local/bin` if none of them is. On Windows it is a `datablinder\bin`
#' folder under `LOCALAPPDATA`. Missing directories are created. A message says
#' whether the shell will find the command where it landed, and what to do if it
#' will not.
#'
#' The command is a copy, but it holds no logic: it calls the installed package,
#' so upgrading `datablinder` upgrades the command too. Run this again after
#' upgrading R itself, which moves the `Rscript` the Windows shim points at.
#'
#' This is the only function in the package that writes a file anywhere
#' permanent, so it asks before it does: it prints the directory and waits for
#' `y`. Any other answer writes nothing, not even the directory. Called where
#' there is nobody to ask, in a script or `Rscript -e`, it is an error rather
#' than a silent write to your home directory. A `dir` inside `tempdir()` is
#' written without asking, since the session takes it away again.
#'
#' @param dir Where to put the command. `NULL` picks a sensible place.
#'
#' @return The path of the installed command, invisibly, or `NULL` invisibly if
#'   you decline.
#'
#' @seealso [blind_file()], which the command calls, and [run_app()] for the
#'   same job in a browser.
#' @export
#' @examples
#' # Into a scratch directory, to show what is written:
#' dir <- file.path(tempdir(), "bin")
#' install_cli(dir)
#' list.files(dir)
install_cli <- function(dir = NULL) {
  script <- db_cli_script()
  if (is.null(dir)) {
    dir <- db_cli_dir()
  }
  if (!db_cli_consent(path.expand(dir))) {
    message("Nothing was written.")
    return(invisible(NULL))
  }
  dir <- db_cli_make_dir(dir)

  target <- file.path(dir, DB_CLI_COMMAND)
  if (!file.copy(script, target, overwrite = TRUE)) {
    stop("Could not write the command to ", target, ".", call. = FALSE)
  }
  if (db_is_windows()) {
    writeLines(db_cli_shim(), paste0(target, ".cmd"))
  } else {
    Sys.chmod(target, "0755")
  }

  message(paste(db_cli_notes(dir, target), collapse = "\n"))
  invisible(target)
}

# Consent ----------------------------------------------------------------

# A file that outlives the session is the user's to allow, so it is asked for
# and not assumed from the call. The temporary directory is the exception: the
# session created it and will take it away, which is where the examples and the
# tests write.
db_cli_consent <- function(dir) {
  if (db_under_tempdir(dir)) {
    return(TRUE)
  }
  if (!db_is_interactive()) {
    stop(
      "install_cli() would write to ", dir, ", which outlives this session, ",
      "so it only runs where it can ask first.\n",
      "Run it from an R console, or skip it: ",
      "Rscript -e 'datablinder::blind_file(\"patients.csv\")' needs nothing ",
      "installed.",
      call. = FALSE
    )
  }
  db_ask_yes_no(paste0("Install the datablinder command in ", dir, "?"))
}

# Through functions of our own, so that the tests can answer and the examples
# never stop for an answer.
db_is_interactive <- function() {
  interactive()
}

db_ask_yes_no <- function(question) {
  db_is_yes(readline(paste0(question, " (y/N) ")))
}

# Silence is no, so that a stray return key does not install anything.
db_is_yes <- function(answer) {
  tolower(trimws(answer)) %in% c("y", "yes")
}

db_under_tempdir <- function(dir) {
  temp <- db_real_path(tempdir())
  dir <- db_real_path(dir)
  identical(dir, temp) || startsWith(dir, paste0(temp, "/"))
}

db_cli_script <- function() {
  script <- system.file("scripts", DB_CLI_COMMAND, package = "datablinder")
  if (script == "") {
    stop(
      "The datablinder package has no copy of the command to install. ",
      "Please report this as a bug.",
      call. = FALSE
    )
  }
  script
}

# The first candidate the shell already searches and the user can write to, so
# that in the common case there is nothing left to do afterwards.
db_cli_dir <- function() {
  dirs <- db_cli_dirs()
  usable <- dirs[db_on_path(dirs) & db_writable(dirs)]
  if (length(usable) > 0L) usable[[1L]] else dirs[[1L]]
}

db_cli_make_dir <- function(dir) {
  dir <- path.expand(dir)
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  }
  if (!dir.exists(dir)) {
    stop("Could not create the directory ", dir, ".", call. = FALSE)
  }
  dir
}

# Windows cannot run a file without an extension, so it runs this instead. The
# path to Rscript is written out in full: the R installer for Windows does not
# put R on the PATH, so "Rscript" alone would often not be found.
db_cli_shim <- function() {
  c(
    "@echo off",
    paste0(db_quote(db_rscript()), " ", db_quote("%~dp0datablinder"), " %*")
  )
}

db_rscript <- function() {
  exe <- if (db_is_windows()) "Rscript.exe" else "Rscript"
  normalizePath(file.path(R.home("bin"), exe), mustWork = FALSE)
}

# What to tell the user, which depends on whether the shell will find it.
db_cli_notes <- function(dir, target) {
  where <- paste0("The datablinder command is installed in ", dir, ",")
  if (db_on_path(dir)) {
    return(c(
      where,
      "which is already on your PATH. Check it with:",
      "  datablinder --help"
    ))
  }
  c(
    where,
    "which is not on your PATH, so the shell will not find it by name yet.",
    "It works by its full path right away:",
    paste0("  ", db_quote(target), " --help"),
    "For the short name, add that folder to your PATH:",
    db_cli_path_hint(dir)
  )
}

db_cli_path_hint <- function(dir) {
  if (db_is_windows()) {
    return(c(
      "  Settings > Edit environment variables for your account > Path > New",
      "  then open a new terminal."
    ))
  }
  c(
    paste0("  echo 'export PATH=\"", dir, ":$PATH\"' >> ~/.zshrc"),
    "  (~/.bashrc for bash), then open a new terminal and check with:",
    "  echo $PATH"
  )
}

# PATH -------------------------------------------------------------------

db_on_path <- function(dir) {
  db_comparable_path(dir) %in% db_comparable_path(db_path_dirs())
}

db_path_dirs <- function() {
  entries <- strsplit(Sys.getenv("PATH"), .Platform$path.sep, fixed = TRUE)[[1L]]
  entries[nzchar(entries)]
}

# Two spellings of one directory must compare equal: "~/bin" and "/Users/x/bin",
# a trailing slash or not, and on Windows either case.
db_comparable_path <- function(paths) {
  if (length(paths) == 0L) {
    return(character())
  }
  normal <- normalizePath(path.expand(paths), winslash = "/", mustWork = FALSE)
  normal <- sub("/$", "", normal)
  if (db_is_windows()) tolower(normal) else normal
}

# The same, for one directory that may not exist yet: normalise as much of it as
# does and keep the rest. Without this a directory under tempdir() that has not
# been created compares unequal to tempdir() itself, because macOS resolves
# /var to /private/var only for a path that is there.
db_real_path <- function(dir) {
  existing <- path.expand(dir)
  rest <- character()
  while (!file.exists(existing) && dirname(existing) != existing) {
    rest <- c(basename(existing), rest)
    existing <- dirname(existing)
  }
  full <- paste(c(db_comparable_path(existing), rest), collapse = "/")
  if (db_is_windows()) tolower(full) else full
}

# A directory can be written to if it exists and is writable, or if it does not
# exist but its nearest existing parent is: that one we can create.
db_writable <- function(dirs) {
  vapply(dirs, function(dir) {
    dir <- path.expand(dir)
    while (!dir.exists(dir) && dirname(dir) != dir) {
      dir <- dirname(dir)
    }
    file.access(dir, mode = 2L)[[1L]] == 0L
  }, logical(1), USE.NAMES = FALSE)
}

db_is_windows <- function() {
  .Platform$OS.type == "windows"
}

# Quote a path, because Windows home directories have spaces in them.
db_quote <- function(path) {
  paste0("\"", path, "\"")
}
