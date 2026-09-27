# Other packages for fake and anonymised data

Several R packages make fake or anonymised data, and they are not
interchangeable — they are built for different jobs. This page is here
to help you pick the right one, which is sometimes not this one.

## The question that separates them

**What is the fake data for?**

If it is for *writing code that will later run on the real data*, you
want the structure preserved exactly and you do not care whether the
numbers are analytically faithful. That is what `datablinder` does.

If it is for *analysing*, so that a result computed on the synthetic
data is a valid estimate of the result on the real data, you want the
relationships between columns preserved — and you want a package built
for that. `datablinder` deliberately destroys those relationships and is
the wrong tool.

## How the packages line up

| Package | Starts from | Built to preserve | Typical use |
|----|----|----|----|
| **datablinder** | an existing file | structure: columns, classes, formats, file type | writing code against a copy, then running it on the real data |
| [synthpop](https://cran.r-project.org/package=synthpop) | an existing data frame | the joint distribution, so analyses remain valid | releasing synthetic microdata others can analyse |
| [sdcMicro](https://cran.r-project.org/package=sdcMicro) | an existing data frame | the real values, where they are safe to keep | statistical disclosure control: measuring re-identification risk, suppressing and recoding |
| [simstudy](https://cran.r-project.org/package=simstudy) | a specification you write | whatever you specify | simulation studies, power calculations |
| [charlatan](https://cran.r-project.org/package=charlatan), [fakir](https://cran.r-project.org/package=fakir) | nothing | nothing — values are invented from scratch | test fixtures, teaching datasets, realistic-looking names and addresses |
| [FakeDataR](https://cran.r-project.org/package=FakeDataR) | an existing data frame | structure, loosely | the same goal as datablinder |

Two things follow from that table.

**`sdcMicro` and `datablinder` are not substitutes.** Disclosure control
keeps real values and manages the risk of them being traced back to
someone. Blinding keeps no real values at all, and accepts that the
structure is disclosed instead. If your obligation is to release a
version of the real data, you want disclosure control. If your
obligation is never to let the real data leave the building, you want a
blinded copy.

**`synthpop` and `datablinder` pull in opposite directions.** Preserving
the joint distribution is what makes synthetic data analytically useful,
and it is also what makes it carry information about the real records.
`datablinder` gives that up entirely: it blinds each column on its own,
which is why nothing you compute on the copy means anything, and why the
copy tells a reader comparatively little.

## FakeDataR, which came first

[FakeDataR](https://cran.r-project.org/package=FakeDataR) (MIT) has the
same goal as this package, and three of its ideas are used here:
recognising sensitive columns by matching their names against a word
list, printing a short description of the fake data to paste into a
chat, and validating the copy against the original by comparing classes
and missingness. Parts of the name word lists in `datablinder` are
adapted from it.

The difference is in what `datablinder` refuses to do, because each of
these breaks code written against the copy when it meets the real data:

- draw numeric columns uniformly between the real minimum and maximum,
  or resample the real values
- turn a 0/1 double into decimals, so that `table(x)`, `x == 1` and
  `factor(x)` behave differently
- keep real category labels by default
- return 30 rows instead of the input’s row count
- change types by default: percent strings to numbers, yes/no text to a
  factor, date text to `POSIXct`

Each of those has a test in this package proving it does not happen.
`datablinder` also reads and writes the file itself — Excel, SPSS,
Stata, Parquet, delimited text — rather than working on R objects only,
and it ships a local app and a command line script.

## The rule of thumb

``` r

library(datablinder)
```

Ask what happens to the code you write. If the code is going to be run
again on the real data, the thing that must be identical is the
structure, and a difference in the numbers is free. That is the case
`datablinder` is built for, and it is the case where preserving
relationships would be a liability rather than a feature.
