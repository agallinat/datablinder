# Blind a data file in a browser

Opens a small app in the default browser: choose a file, set the
options, press *Blind*, read the summary and download the blinded copy.
It runs on `127.0.0.1`, so everything stays on this computer, and the
uploaded file is deleted when the app closes.

## Usage

``` r
run_app()
```

## Value

Nothing. Called to run the app, which stops when the browser tab or the
R session is interrupted.

## Details

This reduces the risk of disclosing the real data. It is not a formal
privacy guarantee: the column names, classes, row count and the broad
shape of each column stay visible.

In RStudio the app can also be started from *Addins* \> *Blind a data
file*.

## See also

[`blind_file()`](https://agallinat.github.io/datablinder/reference/blind_file.md)
for the same job at the console.

## Examples

``` r
if (interactive()) {
  run_app()
}
```
