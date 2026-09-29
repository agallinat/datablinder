# Sharing sensitive data with an AI assistant

You have a data file. You want an analysis, and you would like an AI
assistant to write the code. The file is confidential, so you cannot
paste it into a chat.

The way round it is to share a file with the same *structure* and none
of the same *contents*: same columns, same classes, same file format,
fake values. Write the code against that, then run the code on the real
file.

``` r

library(datablinder)
```

## Step 1: make the blinded copy

``` r

# Stand in for your confidential file.
real <- file.path(tempdir(), "patients.csv")
write.csv(
  data.frame(
    patient_id = sprintf("P-%05d", 1:60),
    age = sample(21:88, 60, replace = TRUE),
    region = sample(c("North", "South", "East"), 60, replace = TRUE),
    treated = sample(0:1, 60, replace = TRUE),
    weight_kg = round(rnorm(60, 78, 9), 1)
  ),
  real,
  row.names = FALSE
)

summary <- blind_file(real, seed = 1)
```

That wrote `patients_blinded.csv` next to the input. The blinded file is
the one you share.
[`blind_file()`](https://agallinat.github.io/datablinder/reference/blind_file.md)
also returns a summary, which prints when you do not assign it — here it
is in `summary`.

## Step 2: read the summary before you share anything

The summary is the list of decisions the package made, and reading it is
the step people skip. You are looking for a column whose description
does not match what you know the column to be — a code blinded as free
text, an identifier blinded as a category. Those are the cases to catch.

``` r

summary
#> Blinded copy written to /tmp/RtmpxCpcbp/patients_blinded.csv
#> 
#>   patient_id  character  new IDs, same shape (A-00000)
#>   age         integer    numeric, synthetic values
#>   region      character  3 categories -> A, B, C
#>   treated     integer    discrete numbers, same values
#>   weight_kg   numeric    numeric, synthetic values
#> Rows: 60
#> Leak check: passed
#> Exact numeric or date coincidences: 59 (expected with rounded values and shifted date ranges)
```

It describes the blinded data only, so it is safe to paste into a chat.
Get it as plain lines with
[`format()`](https://rdrr.io/r/base/format.html):

``` r

head(format(summary), 3)
#> [1] "Blinded copy written to /tmp/RtmpxCpcbp/patients_blinded.csv"
#> [2] ""                                                            
#> [3] "  patient_id  character  new IDs, same shape (A-00000)"
```

One thing to look at before you paste: the first line is the path the
copy was written to, and a path can carry information of its own — a
client name, a project codename, your user name. If that matters, drop
the first line, or write the copy somewhere neutral with `output`:

``` r

lines <- format(summary)
cat(lines[-(1:2)], sep = "\n")   # the column descriptions, without the path
#>   patient_id  character  new IDs, same shape (A-00000)
#>   age         integer    numeric, synthetic values
#>   region      character  3 categories -> A, B, C
#>   treated     integer    discrete numbers, same values
#>   weight_kg   numeric    numeric, synthetic values
#> Rows: 60
#> Leak check: passed
#> Exact numeric or date coincidences: 59 (expected with rounded values and shifted date ranges)
```

## Step 3: give the assistant the file and the summary

The summary is worth pasting along with the file, because it tells the
assistant what each column is before it writes a line of code. Something
like:

> Attached is a blinded copy of a data file: the columns, types and
> formats are real, the values are synthetic. Write R code that runs on
> the real file, which has the same structure. Here is what each column
> is:
>
> *(paste the summary here)*
>
> I want: *(your analysis)*.
>
> The synthetic values carry no relationships between columns, so don’t
> draw any conclusions from the numbers themselves — just write the
> code.

That last line matters. Columns are blinded independently, so any
correlation or group difference the assistant might notice in the copy
is an artefact.

## Step 4: run what comes back on the real file

``` r

# Pretend this arrived from the assistant, written against the blinded copy.
analysis <- function(path) {
  d <- read.csv(path)
  aggregate(weight_kg ~ region + treated, data = d, FUN = mean)
}

analysis(file.path(tempdir(), "patients_blinded.csv"))  # structurally right
#>   region treated weight_kg
#> 1      A       0  76.30000
#> 2      B       0  77.40909
#> 3      C       0  72.85556
#> 4      A       1  77.25556
#> 5      B       1  79.72857
#> 6      C       1  77.56000
nrow(analysis(real))                                    # and it runs on the real file
#> [1] 6
```

The output from the blinded copy is meaningless as a result, and correct
as a *shape*. That is the whole trade.

## Four options that come up in this workflow

`keep_labels = TRUE` when the code has to filter on real category
values. By default `region` becomes `A`, `B`, `C`, and
`region == "North"` will not match anything, so the assistant cannot
write that line for you:

``` r

blinded <- blind_data(
  data.frame(region = rep(c("North", "South"), 20)),
  keep_labels = TRUE,
  seed = 1
)
unique(blinded$region)
#> [1] "North" "South"
```

Only use it when the labels themselves are not sensitive.

`blind_names = TRUE` when the column names are the confidential part.
They become `col_01`, `col_02`, and SPSS or Stata variable labels are
dropped too, since those often describe sensitive content. The cost is
that the assistant no longer knows what anything means.

`keep_real` when the code cannot be written without a whole column as it
is: a treatment arm, a study visit, a site. Those columns are copied
over untouched, so they are genuinely shared, which makes this the one
option that discloses real data:

``` r

trial <- data.frame(
  arm = rep(c("placebo", "active"), 20),
  score = round(seq(41.2, 60.7, length.out = 40), 1)
)
blinded <- blind_data(trial, keep_real = "arm", seed = 1)
unique(blinded$arm)            # real, so the assistant can filter on it
#> [1] "placebo" "active"
identical(blinded$score, trial$score)  # and everything else is still fake
#> [1] FALSE
```

The summary names every column kept, and the leak check says plainly
that it cannot vouch for them. Use it only for columns that identify
nobody, on their own or beside the others, and read
[`vignette("limits")`](https://agallinat.github.io/datablinder/articles/limits.md)
first. If you only need the categories and not the contents,
`keep_labels = TRUE` is the lighter tool.

`rows` when the real file is too short to detect types well, or when the
code you expect back needs more room to work: on five rows there is
little to tell an identifier from a measurement. It cannot be combined
with `keep_real`, since a kept column stays matched to the rest of its
row.

## Doing it without writing R

[`run_app()`](https://agallinat.github.io/datablinder/reference/run_app.md)
opens a small app on `127.0.0.1`, so the file never leaves the computer:
choose a file, set the options, press **Blind**, read the summary, copy
it with one button, download the copy. In RStudio it is also under
*Addins* \> *Blind a data file*.

From a terminal, with nothing to install beyond the package:

``` bash
Rscript -e 'datablinder::blind_file("patients.csv")'
```

## Before you send it

Read
[`vignette("limits")`](https://agallinat.github.io/datablinder/articles/limits.md).
The blinded copy reduces the risk of disclosing values; it is not a
formal privacy guarantee, and some things about your data stay visible
on purpose.
