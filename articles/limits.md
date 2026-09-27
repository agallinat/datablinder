# What datablinder does not protect you from

This page is the one to read before deciding whether you are allowed to
share a blinded file. It is deliberately the least flattering page in
the documentation.

``` r

library(datablinder)
```

## It is not a formal privacy guarantee

`datablinder` reduces the risk of disclosing the values in your data. It
does not implement differential privacy, *k*-anonymity, or any other
model with a provable bound, and it makes no claim of one.

What it does is structural: character, factor, label and identifier
columns are built from the *shape* of the real values rather than from
the values, and any overlap with the real column is treated as a bug — a
hard failure that stops anything from being written.

## The structure stays visible, on purpose

This is the part people miss. All of the following survive into the
blinded copy, because they are exactly what makes the code work:

- every column name, unless `blind_names = TRUE`
- every column’s class and storage type
- the number of rows, unless you set `rows`
- the share of missing values in each column
- the number of categories or factor levels in each column
- the broad shape of every numeric distribution, and its approximate
  range
- sheet names, in a workbook

So if the *structure itself* is confidential — the fact that you hold a
column called `hiv_status`, or that your file has exactly 1,204 rows, or
that a measurement ranges where it does — a blinded copy does not solve
your problem. Use `blind_names = TRUE`, and then think again about
whether to share the file at all.

## The blinded data is for writing code, not for analysis

Columns are blinded independently. No relationship between columns is
preserved, and none is even attempted.

``` r

d <- data.frame(x = 1:200, y = 1:200 * 2)          # perfectly correlated
cor(d$x, d$y)
#> [1] 1

fake <- blind_data(d, seed = 1)
round(cor(fake$x, fake$y), 2)                       # the relationship is gone
#> [1] 0.1
```

So no correlation, model coefficient, group difference, cross-tabulation
or plot made from the blinded copy tells you anything about the real
data. Results will be structurally similar and numerically meaningless.
If an AI assistant interprets the numbers it sees in the copy, it is
interpreting noise — say so in your prompt.

## Some code will not survive the trip

- **Code that depends on the content of free text.** Free text becomes
  placeholder words, so regular expressions, keyword searches and text
  mining written against the copy will not do anything useful on the
  real file.
- **Code that relies on relationships between columns.** A filter such
  as `age > 60 & treated == 1` will run, but the number of rows it
  returns in the copy means nothing.
- **Code that relies on a particular real value existing.** By default
  category values become `A`, `B`, `C`, so `region == "North"` matches
  nothing. That is what `keep_labels = TRUE` is for, and it keeps real
  labels — only use it when the labels are not themselves sensitive.

## Detection can be wrong, and the summary is where you see it

Type detection works from the values, which means it needs values to
work from. On a short file there is little to tell an identifier from a
measurement, or a code from free text. A column detected as the wrong
type is still blinded, and still leak-checked, but it may be blinded in
a way that breaks the code you get back — or, more importantly, in a way
you did not expect.

The summary printed after every run is the list of those decisions. Read
it. That is the whole reason it exists and gets a *Copy* button in the
app.

## Exact numeric coincidences are reported, not forbidden

You will sometimes see a line like this:

    Leak check: passed
    Exact numeric or date coincidences: 33 (expected with rounded values and shifted date ranges)

That count is expected and is not a leak of anything usable. A column of
ages rounded to whole years has only so many distinct values available;
date ranges are shifted rather than relocated; placeholder words come
from a fixed list. It is reported so that you can see it rather than
have it hidden from you.

The columns where a coincidence *would* mean something — character,
factor, label and identifier — are checked for zero overlap, and a
single match there fails the run.

## What the package never does

- No network access, anywhere.
- No AI or LLM calls, anywhere. Reading, blinding and writing all happen
  on your machine; the app runs on `127.0.0.1`. Sharing the blinded file
  with an assistant is something you do afterwards, deliberately.
- No real value in the output, except category labels under
  `keep_labels = TRUE`.
- No real data value in any message, warning or error. Problems are
  reported by column name and row number only.
- No change to your session’s random number state: `.Random.seed` is put
  back as it was found.

## Not in this version

Preserving relationships between columns, per-column overrides, reading
from a database, and complex objects such as `Seurat` or
`SingleCellExperiment`.
