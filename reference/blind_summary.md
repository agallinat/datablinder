# The summary of a blinded table

[`blind_file()`](https://agallinat.github.io/datablinder/reference/blind_file.md)
returns a `blind_summary` and
[`blind_data()`](https://agallinat.github.io/datablinder/reference/blind_data.md)
hangs one on its result as the `blind_summary` attribute. It describes
the blinded data only, never a real value, so it is safe to paste into a
chat along with the blinded file, and it tells an AI what each column is
before it writes a line of code.

## Usage

``` r
# S3 method for class 'blind_summary'
format(x, ...)

# S3 method for class 'blind_summary'
print(x, ...)
```

## Arguments

- x:

  A `blind_summary`, from
  [`blind_file()`](https://agallinat.github.io/datablinder/reference/blind_file.md)
  or from the `blind_summary` attribute of a
  [`blind_data()`](https://agallinat.github.io/datablinder/reference/blind_data.md)
  result.

- ...:

  Ignored.

## Value

[`format()`](https://rdrr.io/r/base/format.html) returns a character
vector, one element per line.
[`print()`](https://rdrr.io/r/base/print.html) prints those lines and
returns `x` invisibly.

## Details

Printed, it is the output file if there was one, then one line per
column giving the name, the class and what was done, then the row count
and the result of the leak check.
[`format()`](https://rdrr.io/r/base/format.html) returns those same
lines as a character vector, for writing them somewhere instead of
printing them.

Read it before sharing the file. It is the list of decisions the package
made, and a column blinded as a category when it is really an
identifier, or as free text when it is really a code, is the case to
catch.

## See also

[`blind_file()`](https://agallinat.github.io/datablinder/reference/blind_file.md),
[`blind_data()`](https://agallinat.github.io/datablinder/reference/blind_data.md).

## Examples

``` r
fake <- blind_data(mtcars[1:3], seed = 1)
info <- attr(fake, "blind_summary")
info
#>   mpg   numeric  numeric, synthetic values
#>   cyl   numeric  discrete numbers, same values
#>   disp  numeric  numeric, synthetic values
#> Rows: 32
#> Leak check: passed
#> Exact numeric or date coincidences: 9 (expected with rounded values and shifted date ranges)
format(info)
#> [1] "  mpg   numeric  numeric, synthetic values"                                                  
#> [2] "  cyl   numeric  discrete numbers, same values"                                              
#> [3] "  disp  numeric  numeric, synthetic values"                                                  
#> [4] "Rows: 32"                                                                                    
#> [5] "Leak check: passed"                                                                          
#> [6] "Exact numeric or date coincidences: 9 (expected with rounded values and shifted date ranges)"
```
