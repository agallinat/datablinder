# datablinder: Synthetic Look-Alike Copies of Sensitive Data Files

Turns a data file into a blinded copy: the same columns, the same R
classes, the same file format, values that look roughly similar, and not
one real value in it. Share the copy, get analysis code back, run that
code on the real file.

## Details

Everything in the package is built around one promise: code written
against the blinded copy runs unchanged on the real data. Integers stay
integers, a 0/1 column stays 0/1, dates keep their format, a factor
keeps its number of levels, and no column ever changes class.

## The functions

- [`blind_file()`](https://agallinat.github.io/datablinder/reference/blind_file.md)
  reads a data file, blinds every column of every sheet and writes the
  copy next to the input in the same format.

- [`blind_data()`](https://agallinat.github.io/datablinder/reference/blind_data.md)
  does the same to a data frame already in memory.

- [`run_app()`](https://agallinat.github.io/datablinder/reference/run_app.md)
  does it in a small app in the browser, on `127.0.0.1`.

- [`install_cli()`](https://agallinat.github.io/datablinder/reference/install_cli.md)
  puts a `datablinder` command where the shell can find it.

The first three all produce a
[blind_summary](https://agallinat.github.io/datablinder/reference/blind_summary.md):
a short description of the blinded data, and of it only, to paste into a
chat along with the file.

## The options

Four, the same everywhere: `blind_names`, `keep_labels`, `rows` and
`seed`, described in
[`blind_data()`](https://agallinat.github.io/datablinder/reference/blind_data.md).
Detection thresholds are internal constants, and there is no
configuration file.

## Limits

- This is not a formal privacy guarantee. It reduces the risk of
  disclosing the real values. The column names, the classes, the row
  count, the share of missing values, the number of categories and the
  broad shape of every distribution all stay visible, on purpose,
  because that is what makes the code work.

- Read the summary before sharing the file. It is the list of decisions
  the package made, and a column blinded as a category when it is really
  an identifier is the case to catch.

- The blinded data is for writing code, not for analysis. Columns are
  blinded independently, so no correlation, model coefficient or
  cross-tabulation on the copy means anything about the real data.

- No network access, and no AI or LLM calls, anywhere in the package.
  Sharing the blinded file with an AI is a thing you do afterwards,
  deliberately.

## See also

Useful links:

- <https://agallinat.github.io/datablinder/>

- <https://github.com/agallinat/datablinder>

- Report bugs at <https://github.com/agallinat/datablinder/issues>

## Author

**Maintainer**: Alex Gallinat <baloo.142@gmail.com>
