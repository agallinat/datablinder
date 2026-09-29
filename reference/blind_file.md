# Blind a data file

Reads a data file, blinds every column of every sheet, and writes a copy
in the same format next to the input, keeping the delimiter, decimal
mark, encoding and sheet names of a text file or workbook, and the
variable labels and display formats of an SPSS or Stata file. Code
written against the copy runs unchanged on the real file.

## Usage

``` r
blind_file(
  path,
  output = NULL,
  blind_names = FALSE,
  keep_labels = FALSE,
  keep_real = NULL,
  rows = NULL,
  seed = NULL
)
```

## Arguments

- path:

  Path to a CSV, TSV, Excel, SPSS, Stata, RDS or Parquet file. An RDS
  file must hold a data frame. Parquet needs the `arrow` package.

- output:

  Where to write the copy. The default adds `_blinded` to the input's
  name. An `.xls` input is written as `.xlsx`, which is the only Excel
  format that can be written.

- blind_names:

  Rename the columns to `col_01`, `col_02`... and drop the variable
  labels, which often describe sensitive content.

- keep_labels:

  Keep the real factor levels and category values, for when code has to
  filter on them. `FALSE` replaces them with `A`, `B`, `C`...

- keep_real:

  Names of columns to copy across **unchanged, with their real values**,
  for columns that carry no sensitive information and that code has to
  use as they are, such as a treatment arm or a study visit. These
  columns keep their real names even under `blind_names`, and are named
  in the summary and excluded from the leak check. Cannot be combined
  with `rows`. Use it sparingly: see the warning below.

- rows:

  Number of rows to generate. `NULL` keeps the input's row count.

- seed:

  A seed, for a reproducible copy. `NULL` picks one without disturbing
  the session's random number stream.

## Value

A `blind_summary`, printed when called at the console, describing the
blinded file one column at a time. Paste it into a chat to tell an AI
what the data looks like.

## Details

This reduces the risk of disclosing the real data. It is not a formal
privacy guarantee: the column names, classes, row count and the broad
shape of each column stay visible.

## What happens to each column

Types are decided by values, not only by storage class: a double holding
nothing but 0 and 1 is binary, and a double holding whole numbers with
few distinct values is discrete. That is what keeps `table(x)`, `x == 1`
and `factor(x)` behaving the same way on both copies.

- Continuous numeric: drawn from a smoothed inverse CDF of the real
  column, so the shape survives; slightly shifted minimum and maximum,
  the same number of decimals, the same sign, the same share of exact
  zeros.

- Discrete numeric, whole numbers with few distinct values, 0/1
  included: the same set of values in similar proportions.

- Factor, ordered factor, character with few distinct values,
  `haven_labelled`: the same number of levels or categories in similar
  proportions, relabelled `A`, `B`, `C`... unless `keep_labels`. Order,
  unused levels and `haven` codes kept.

- Logical: a similar share of `TRUE`.

- `Date`, `POSIXct`: dates in a slightly shifted range, same timezone.
  Dates that were text in the file stay text, in the same format.

- Identifier, meaning nearly all values distinct or a name like
  `patient_id`: new unique values of the same shape; a repeated ID
  repeats a similar number of times.

- Email, phone, URL: obviously fake values of the same shape, at
  `example.com`.

- Fixed-shape text, such as postcodes and codes with leading zeros:
  random letters, digits and punctuation in the same positions.

- Free text: placeholder words of similar length.

- Constant or all-`NA`: all-`NA` stays; a constant number stays;
  constant text is replaced.

Every column keeps its share of missing values, and a text file keeps
the way it wrote them. Code that depends on the content of free text, on
a particular real value existing, or on a relationship between two
columns will not work.

## Columns kept real

`keep_real` names columns that are copied over untouched, so their real
values end up in the shared copy. It exists because code often has to
use a real value to be useful at all, as in `arm == "placebo"`, and
hand-editing the blinded file back is worse than asking for it.

It is also the one way to make this package disclose real data, so the
decision is yours and it is worth making slowly:

- A column that is harmless by itself can still identify someone in
  combination with the others. A real date of birth, postcode or site,
  next to a real sex and a real visit date, can be enough, even with
  every name blinded.

- The rows still line up. A kept column stays matched to the rest of its
  row, which is why `rows` cannot be used at the same time.

- The summary says which columns were kept, and the leak check cannot
  vouch for them. Read both before sharing the file.

The safe default is not to use it. If a column is only needed for its
categories and not its contents, `keep_labels` is usually enough.

## See also

[`blind_data()`](https://agallinat.github.io/datablinder/reference/blind_data.md)
to do the same to a data frame.

## Examples

``` r
csv <- file.path(tempdir(), "cars.csv")
write.csv(mtcars, csv, row.names = FALSE)
blind_file(csv, seed = 1)
#> Blinded copy written to /tmp/RtmpEtPg16/cars_blinded.csv
#> 
#>   mpg   numeric  numeric, synthetic values
#>   cyl   integer  discrete numbers, same values
#>   disp  numeric  numeric, synthetic values
#>   hp    integer  numeric, synthetic values
#>   drat  numeric  numeric, synthetic values
#>   wt    numeric  numeric, synthetic values
#>   qsec  numeric  numeric, synthetic values
#>   vs    integer  discrete numbers, same values
#>   am    integer  discrete numbers, same values
#>   gear  integer  discrete numbers, same values
#>   carb  integer  discrete numbers, same values
#> Rows: 32
#> Leak check: passed
#> Exact numeric or date coincidences: 21 (expected with rounded values and shifted date ranges)
```
