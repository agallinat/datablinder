# datablinder: Specification (R package + Shiny app)

## 1. The idea

> "I have this data. I want an analysis and an output. I want an AI to write the code. But the data is sensitive or proprietary, so I can't drop it into a chat."

`datablinder` is an R package that takes a data file (or a data frame) and produces a **blinded copy**: the same columns, R classes, formats and file type, with roughly similar values, but every value is fake. The user shares the blinded file with the AI or a collaborator, gets working code back, and runs that code on the real data.

**Simplicity is the main design goal.** Input → output, four options, no configuration files, no reports, no network access, no AI or LLM calls of any kind.

The one success criterion: **code written against the blinded data runs unchanged on the real data**, and gives structurally similar results (the same factor levels count, binary columns still binary, integers still integers, dates still dates in the same format).

## 2. Prior art: FakeDataR, and why this package differs

FakeDataR (CRAN, MIT) has a similar goal. Studying it showed some behaviours that break our success criterion. **Tests must prove datablinder does not do these things:**

- Numeric columns are either drawn uniformly between the real min and max (the shape is lost and the real extremes define the bounds) or resampled from the real values (real values leak).
- Binary 0/1 and whole-number columns stored as doubles become decimals (e.g. `am` = 0.24, `cyl` = 5.07), so `table()`, `x == 1` and `factor(x)` behave differently.
- Real category labels are kept by default.
- The default output has 30 rows instead of the input's row count.
- Default "normalisation" changes types (percent strings → numbers, yes/no → ordered factor, date strings → POSIXct), so code written on the fake data may fail on the real data.
- It works on R objects and writes CSV/RDS/Parquet only: no Excel, SPSS or Stata, and no "same file in, same file out".
- Sensitive columns are detected by name only; there is no GUI.

Good ideas worth reusing (FakeDataR is MIT-licensed, so credit it in the README if any code or pattern lists are adapted): a regex list for recognising sensitive column names, a short text description of the fake data for pasting into a chat, and a validation function comparing classes and missingness.

## 3. What it does

### Supported files
| Format | Read | Write |
|---|---|---|
| CSV / TSV | `data.table::fread` | `data.table::fwrite`, keeping delimiter, decimal mark and encoding (UTF-8 or Latin-1) |
| Excel `.xlsx` / `.xls` | `readxl` (every sheet) | `writexl` (`.xlsx`, same sheet names) |
| SPSS `.sav`, Stata `.dta` | `haven` (keeps labelled values and variable labels) | `haven` |
| R `.rds` | `readRDS` (must contain a data frame; clear error otherwise) | `saveRDS` |
| Parquet | `arrow` (Suggests, only if installed) | `arrow` |

Output goes to `<name>_blinded.<ext>` next to the input unless another path is given.

### A short summary after every run
One line per column describing the **blinded** data only, for example:
```
age        integer   numeric, synthetic values
sex        factor    2 levels → A, B
visit_date Date      synthetic dates, format %d/%m/%Y
patient_id character new IDs, same shape (P-000000)
Leak check: passed
```
It is printed in the console and shown in the app with a *Copy* button, so it can be pasted into a chat to give the AI context. It is a `blind_summary` object with a `print` method.

## 4. The four options

| Argument | Default | Meaning |
|---|---|---|
| `blind_names` | `FALSE` | Rename columns to `col_01, col_02…`. Variable labels (SPSS/Stata) are removed too, since they often describe sensitive content |
| `keep_labels` | `FALSE` | `FALSE`: factor levels and category values become `A, B, C…`. `TRUE`: real labels kept, for when code must filter on them (`region == "North"`) and the labels aren't sensitive |
| `rows` | `NULL` (same as input) | Number of rows to generate |
| `seed` | `NULL` (random) | For a reproducible blinded file |

Detection thresholds are internal constants, not options.

## 5. How each column is blinded

Columns are handled independently (relationships between columns are deliberately not preserved). **Types are decided by values, not only by storage class**: a double column holding only 0 and 1 is binary; a double holding whole numbers with few distinct values is discrete.

| Detected type | Blinded column |
|---|---|
| Continuous numeric | Sampled from a smoothed inverse CDF of the real values (`quantile()` on ~50 probabilities, small monotone noise, `approx()`), with slightly shifted min and max, the same number of decimals and sign constraints, and the same share of exact zeros. Class kept (`integer` stays `integer`) |
| Discrete numeric (whole numbers, ≤ 15 distinct values, incl. 0/1) | Same set of values, similar proportions. Class kept |
| Factor / ordered factor | Same number of levels, relabelled `A, B, C…` (or kept), similar proportions, order kept. Unused levels kept as levels |
| Character with few distinct values | Same treatment as a factor, stays `character` |
| Logical | Similar proportion of `TRUE` |
| `haven_labelled` (SPSS/Stata) | Codes kept, value labels relabelled unless `keep_labels` |
| `Date`, `POSIXct` | Random dates in a slightly shifted range, same timezone. If the dates were **text** in the file, the output is text in the **same format** |
| Identifier (mostly unique values, or name matching the sensitive-name list) | New unique values of the same shape (`P-004213` → `P-381907`); if IDs repeat, a similar number of rows per ID |
| Email, phone, URL (pattern match on values) | Obviously fake values of the same shape (`user_3f9a@example.com`) |
| Other text with a fixed shape (postcodes, leading-zero codes) | Random strings with letters, digits and punctuation in the same positions |
| Free text | Placeholder words with a similar length |
| Constant / all `NA` | All `NA` stays; a constant number stays; a constant text is replaced |

For every column, the **share of missing values** is kept, and so is how missing values are written in text files (empty, `NA`, `-99`…).

Other things preserved: column order, the object class (`data.frame`, `tibble`, `data.table`), and SPSS/Stata display formats.

## 6. Safety rules

- No real value appears in the output, except category labels when `keep_labels = TRUE`. A **leak check** runs after every blinding: character, factor, label and identifier columns must have zero overlap with the original (hard failure); exact numeric matches are counted and reported (a few coincidences can happen with rounded data).
- Real data values are never printed in messages, warnings or errors; refer to column names and row numbers only.
- No network access anywhere in the package.
- The RNG must not disturb the user's session: save and restore `.Random.seed` around any seeded work.
- README, help pages and the app state plainly that this reduces disclosure risk but gives no formal privacy guarantee, and that column structure and row counts remain visible.

## 7. Interfaces

### R functions (the core)
```r
blind_file("patients.xlsx")                          # → patients_blinded.xlsx, returns the summary
blind_file("data.sav", output = "shared/fake.sav", blind_names = TRUE, rows = 200, seed = 1)
fake <- blind_data(my_df, keep_labels = TRUE)       # data frame in, data frame out (summary as attribute)
run_app()                                            # open the Shiny app
install_cli()                                        # put the `datablinder` command on the PATH
```
Four exported functions. `blind_file()` = read + `blind_data()` + write.

### Shiny app
Built with `shiny` + `bslib`, launched by `run_app()` on `127.0.0.1` in the default browser. Everything runs on the user's machine.

Layout (`bslib::page_sidebar`):
- **Sidebar**: file upload; checkboxes *Blind column names* and *Keep category labels*; numeric inputs *Rows* (empty = same) and *Seed* (empty = random); a **Blind** button; a **Download blinded file** button that appears when done.
- **Main area**: the summary with a *Copy* button (a few lines of JavaScript, no extra package), and a preview of the first 10 rows of the blinded data only.
- A short note at the bottom: what the tool does and doesn't guarantee.

Details: raise `shiny.maxRequestSize` (e.g. 1 GB) inside `run_app()`; delete the uploaded temp file after processing; for Excel, blind every sheet and show a sheet selector in the preview; show a progress indicator for large files.

Also register an **RStudio addin** ("Blind a data file") that calls `run_app()`, so non-coders using RStudio can start it from a menu.

### Command line (thin wrapper)
A script in `inst/scripts/datablinder` using `Rscript` and base `commandArgs()` (no extra dependency):
```bash
datablinder patients.csv --blind-names --rows 200 --seed 42
```
The four options plus `--output`, `--help` and `--version`. Exit status is non-zero if the leak check fails, or if the file cannot be read or written.

`install_cli(dir = NULL)` puts that script where the shell can find it, on all three platforms: it copies the script, adds the `.cmd` shim Windows needs to run an extensionless file (with the full path to `Rscript`, which the Windows installer does not put on the PATH), and says whether the directory it used is on the user's PATH and what to add if it is not. The default directory is the first of `~/.local/bin`, `~/bin`, `/usr/local/bin` that is on the PATH and writable, and a folder under `LOCALAPPDATA` on Windows. No `sudo`, and no shell configuration file is ever edited by the package.

The README leads with the setup-free alternative, `Rscript -e 'datablinder::blind_file("patients.csv")'`, which works everywhere the package does.

## 8. Package setup

- Imports: `shiny`, `bslib`, `data.table`, `readxl`, `writexl`, `haven`, plus base `stats`/`utils`. Suggests: `arrow`, `testthat` (3rd edition), `tibble`.
- roxygen2 documentation; `R CMD check` with no errors or warnings; license MIT.

```
datablinder/
  DESCRIPTION  NAMESPACE  LICENSE  README.md  NEWS.md
  CLAUDE.md  SPEC.md
  R/
    blind_file.R     # exported: read, blind, write
    blind_data.R     # exported: the per-column dispatcher
    run_app.R        # exported
    cli.R            # the command line wrapper's logic, tested without a shell
    install_cli.R    # exported: put the command where the shell can find it
    io.R             # read/write per format, remembering format details
    detect.R         # column type detection + thresholds
    blinders.R       # one function per detected type
    check.R          # leak check
    summary.R        # blind_summary object and print method
    rng.R            # seed handling that restores .Random.seed
  inst/
    app/app.R        # or ui/server functions in R/app_*.R
    scripts/datablinder
    rstudio/addins.dcf
  tests/testthat/
    fixtures/        # small CSV (comma and semicolon/decimal-comma), XLSX with 2 sheets, SAV, DTA, RDS
    test-*.R
```

## 9. Tests (testthat)

- **Shape**: for every fixture, same column names (or renamed), order, classes, factor level counts, row count, sheets, and text-file format details.
- **The FakeDataR pitfalls**: 0/1 doubles stay 0/1; whole-number doubles stay whole numbers; row count equals input by default; no type changes; labels relabelled by default.
- **Round trip**: a short analysis script (filter, group, summarise, `lm`, `table`) written for the blinded data runs without error on the original.
- **No leaks**: leak check passes on all fixtures and on randomly generated data frames.
- **Reproducible**: same seed → identical output; the user's `.Random.seed` is unchanged afterwards.
- **Edge cases**: all-`NA` column, one row, accented and non-ASCII text, Latin-1 CSV, mixed-type column, leading-zero codes, duplicated column names, an empty Excel sheet, a 1-million-row CSV in reasonable time.
- **Shiny**: a `shiny::testServer()` test that uploads a fixture, clicks Blind and gets a downloadable file.

## 10. Build order

1. Package skeleton (`usethis`), I/O for CSV/TSV and XLSX with round-trip tests
2. Type detection
3. Blinding functions, one type at a time, with tests
4. Leak check, summary object, `blind_data()` and `blind_file()`
5. SPSS/Stata/RDS/Parquet
6. Shiny app and RStudio addin
7. CLI script
8. README (with a screenshot, a credit to FakeDataR, and a short "limits" section); `R CMD check` clean

## 11. Not in v1

Preserving relationships between columns, per-column overrides, database input, and complex objects (Seurat, SingleCellExperiment, FASTQ). Keep `detect.R` and `blinders.R` independent of `io.R` so these can be added later.
