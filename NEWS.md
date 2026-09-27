# datablinder 0.1.0

First public release.

* Package skeleton.

* Reading and writing delimited text files (CSV/TSV) and Excel workbooks,
  remembering the delimiter, decimal mark, encoding, line endings, byte order
  mark, missing-value text and sheet names needed to write the blinded copy
  back in the same shape.

* Column type detection, by values rather than by storage class, with every
  threshold a named constant in `R/detect.R`.

* Seed handling that always puts `.Random.seed` back as it found it, and one
  blinding function per detected type.

* `blind_data()` and `blind_file()`, the leak check that runs before anything is
  written, and the `blind_summary` object printed after every run.

* SPSS (`.sav`, `.zsav`), Stata (`.dta`), `.rds` and Parquet files, keeping value
  labels, variable labels and display formats, and the class of the data frame
  stored in an `.rds`. Parquet needs the suggested `arrow` package. An SPSS code
  declared user-missing is now treated as the code it is, not as a missing value.

* `run_app()`, a Shiny app on `127.0.0.1` with the four options, the summary and
  a *Copy* button, a preview of the first ten blinded rows (one sheet at a time
  for a workbook) and a download button. Uploads of up to 1 GB are allowed, the
  browser's copy of the upload is deleted as soon as the app has its own, and
  that copy goes when the session ends. Also an RStudio addin, *Blind a data
  file*, that opens the app.

* A command line wrapper, `inst/scripts/datablinder`, with the four options plus
  `--output`, `--help` and `--version`. The summary goes to standard output and
  anything that went wrong to standard error, with an exit status of 1 if the
  file could not be blinded or the leak check failed.

* `install_cli()`, which puts that command where the shell can find it on
  macOS, Linux and Windows: it copies the script to a directory that is on the
  `PATH` where it can, writes the `.cmd` shim Windows needs, and says plainly
  whether the shell will find the command and what to add to the `PATH` if it
  will not. It needs no `sudo` and never edits a shell configuration file.

* A README that leads with the one promise the package makes, shows the three
  ways to run it, and says plainly in a *Limits* section what the blinded copy
  does not give you: no formal privacy guarantee, a structure that stays visible
  on purpose, and no meaning in any analysis of the copy, since columns are
  blinded independently. It credits FakeDataR for the ideas borrowed from it.
  `R CMD check` runs clean.

* Help pages that stand on their own, for anyone who never sees the README:
  `?datablinder` gives the promise, the four functions, the four options and the
  limits; `?blind_data` and `?blind_file` both carry the list of what happens to
  each kind of column; and `?blind_summary` describes the summary object, what
  to look for in it before sharing a file, and `format()` for getting its lines
  as a character vector.
