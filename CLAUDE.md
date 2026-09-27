# CLAUDE.md

This repo is **datablinder**, an R package with a Shiny app: it turns a sensitive data file into a blinded copy with the same structure and fake values, so people can share it with an AI to get analysis code written. The specification is `SPEC.md`: read it before any task and treat it as the source of truth.

## Principles
- **Keep it simple.** Four exported functions (`blind_file`, `blind_data`, `run_app`, `install_cli`) and four options. Don't add arguments, config files, reports or abstractions SPEC.md doesn't ask for. If something seems missing, propose it; don't build it.
- **Code written for the blinded data must run on the real data.** Never change a column's class or type; decide types by values, not only by storage class.
- **No real value in the output** unless `keep_labels = TRUE`.
- **Never print real data values** in messages, warnings, errors, tests or snapshots. Refer to column names and row numbers only.
- **No network access and no LLM/AI calls**, anywhere.
- Don't claim formal privacy guarantees in code, docs or UI text.

## How to work
- Follow the build order in SPEC.md section 10, one step at a time. Run the tests at the end of each step and summarise what's next.
- Write testthat tests alongside each file; `devtools::test()` must pass before a step is done.
- The Shiny app and the CLI script only call exported functions; all logic lives in `R/`.
- Seeded work must save and restore `.Random.seed`; never leave the user's RNG state changed.
- Detection thresholds are named constants at the top of `R/detect.R`.
- Ask before adding any dependency beyond those in SPEC.md section 8.
- Use roxygen2 for documentation; keep `R CMD check` free of errors and warnings.
- Style: tidyverse style guide, base R pipes (`|>`), no tidyverse runtime dependencies.

## Commands
- Load: `devtools::load_all()`
- Tests: `devtools::test()`
- Docs: `devtools::document()`
- Check: `devtools::check()`
- App: `datablinder::run_app()`
