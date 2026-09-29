# Blind a data frame

Returns a copy of `data` with the same columns, classes and formats, the
same number of rows unless `rows` says otherwise, and fake values
throughout. Columns are blinded independently: relationships between
them are not kept.

## Usage

``` r
blind_data(
  data,
  blind_names = FALSE,
  keep_labels = FALSE,
  keep_real = NULL,
  rows = NULL,
  seed = NULL
)
```

## Arguments

- data:

  A data frame, tibble or data.table.

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

A data frame of the same class as `data`, with a `blind_summary`
attribute describing what was done.

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

[`blind_file()`](https://agallinat.github.io/datablinder/reference/blind_file.md)
to do the same to a file.

## Examples

``` r
fake <- blind_data(mtcars, seed = 1)
str(fake)
#> 'data.frame':    32 obs. of  11 variables:
#>  $ mpg : num  13.4 14.4 16.4 19.2 21.3 18.1 30.2 16 18.8 16.8 ...
#>  $ cyl : num  6 6 6 4 8 8 4 4 6 8 ...
#>  $ disp: num  128 109 145 213 423 ...
#>  $ hp  : num  91 209 63 109 78 92 216 178 98 121 ...
#>  $ drat: num  4.23 3.7 3.06 3.19 3.9 3.16 3.19 3.06 3.9 3.07 ...
#>  $ wt  : num  3.29 3.54 3.65 2.17 3.86 ...
#>  $ qsec: num  20 18.6 16.9 18.5 17 ...
#>  $ vs  : num  0 1 0 0 0 0 0 1 1 0 ...
#>  $ am  : num  0 1 0 1 0 0 1 1 1 0 ...
#>  $ gear: num  4 3 3 3 3 4 3 4 3 3 ...
#>  $ carb: num  3 2 2 3 2 1 3 1 4 2 ...
#>  - attr(*, "blind_summary")=List of 4
#>   ..$ tables:List of 1
#>   .. ..$ data:'data.frame':  11 obs. of  3 variables:
#>   .. .. ..$ column: chr [1:11] "mpg" "cyl" "disp" "hp" ...
#>   .. .. ..$ class : chr [1:11] "numeric" "numeric" "numeric" "numeric" ...
#>   .. .. ..$ note  : chr [1:11] "numeric, synthetic values" "discrete numbers, same values" "numeric, synthetic values" "numeric, synthetic values" ...
#>   ..$ leak  :List of 4
#>   .. ..$ passed : logi TRUE
#>   .. ..$ leaked : chr(0) 
#>   .. ..$ matches: Named int [1:6] 8 1 4 7 0 1
#>   .. .. ..- attr(*, "names")= chr [1:6] "mpg" "disp" "hp" "drat" ...
#>   .. ..$ kept   : chr(0) 
#>   ..$ output: NULL
#>   ..$ rows  : int 32
#>   ..- attr(*, "class")= chr "blind_summary"
attr(fake, "blind_summary")
#>   mpg   numeric  numeric, synthetic values
#>   cyl   numeric  discrete numbers, same values
#>   disp  numeric  numeric, synthetic values
#>   hp    numeric  numeric, synthetic values
#>   drat  numeric  numeric, synthetic values
#>   wt    numeric  numeric, synthetic values
#>   qsec  numeric  numeric, synthetic values
#>   vs    numeric  discrete numbers, same values
#>   am    numeric  discrete numbers, same values
#>   gear  numeric  discrete numbers, same values
#>   carb  numeric  discrete numbers, same values
#> Rows: 32
#> Leak check: passed
#> Exact numeric or date coincidences: 21 (expected with rounded values and shifted date ranges)

# cyl copied over with its real values, everything else blinded
arms <- blind_data(mtcars, keep_real = "cyl", seed = 1)
table(arms$cyl) == table(mtcars$cyl)
#> 
#>    4    6    8 
#> TRUE TRUE TRUE 
```
