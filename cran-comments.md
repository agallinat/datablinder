## Submission

This is a new submission.

## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission, so `checking CRAN incoming feasibility` reports one.

## Test environments

* local macOS 14 (aarch64), R 4.4.2
* win-builder, R devel and R release
* R-hub v2: Linux, Windows and macOS
* GitHub Actions:
  * `macos-latest`, R release
  * `windows-latest`, R release
  * `ubuntu-latest`, R devel, release and oldrel-1

All clean apart from the new-submission note.

## Notes for the reviewer

Three things in this package are worth explaining up front.

**`install_cli()` writes outside the session temporary directory, and asks the
user first.** That is the function's entire purpose: it copies a command line
script out of the installed package into a directory on the user's `PATH`, so
that a file can be blinded with `datablinder patients.csv` instead of a line of
R.

Per the policy on the user's home filespace, it writes only with confirmation:
in an interactive session it prints the directory it would write to and waits
for `y`, and any other answer writes nothing, not even the directory. Where
there is nobody to ask, it is an error rather than a silent write. A `dir` inside
`tempdir()` is the only case it writes without asking, which is what the example
and the tests use, so neither the examples nor the tests write anywhere outside
`tempdir()`.

Nothing needs to be installed to use the package from a terminal, which the help
page says before it describes the function:
`Rscript -e 'datablinder::blind_file("patients.csv")'` works as soon as the
package does. The package writes nothing at load time, on attach, or in any
other function.

The default directory is the first of `~/.local/bin`, `~/bin` and
`/usr/local/bin` that is already on the `PATH` and writable, or a folder under
`LOCALAPPDATA` on Windows. It never uses `sudo`, never edits a shell
configuration file, and prints the path it wrote to along with whether the shell
will find the command there.

**The package is about sharing data with AI assistants, but makes no network
requests of any kind.** There are no calls to any web service, model API or
remote host anywhere in the package, and no such calls in the tests, the
vignettes or the Shiny app. Reading, blinding and writing happen entirely on the
user's machine, and `run_app()` binds to `127.0.0.1`. Sharing the blinded copy
with an assistant is something the user does afterwards, outside the package.

The documentation states plainly, in the `DESCRIPTION`, the package help page,
the README, a dedicated vignette and the app itself, that this reduces
disclosure risk and offers no formal privacy guarantee. No formal privacy claim
is made anywhere.

**Some material is adapted from another package.** Parts of two column name word
lists in `R/detect.R` are adapted from FakeDataR (MIT), along with three ideas
credited in the README. Its author, Zobaer Ahmed, is listed in `Authors@R` as
`ctb` and `cph`, and `inst/COPYRIGHTS` records what was adapted and reproduces
the MIT notice that licence requires. Everything else in the package is my own
work.

## Other details

`run_app()` raises `shiny.maxRequestSize` and restores the previous value with
`on.exit()`. Seeded blinding saves and restores `.Random.seed`, so a user's
random number state is never left changed; there is a test for this.
