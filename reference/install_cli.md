# Install the `datablinder` command

Copies the command line wrapper out of the installed package and into a
directory the shell looks in, so that a file can be blinded with
`datablinder patients.csv` instead of a line of R. On Windows a `.cmd`
shim is written beside it, since `cmd.exe` cannot run the script itself.

## Usage

``` r
install_cli(dir = NULL)
```

## Arguments

- dir:

  Where to put the command. `NULL` picks a sensible place.

## Value

The path of the installed command, invisibly, or `NULL` invisibly if you
decline.

## Details

Nothing has to be installed to use the package from a terminal:
`Rscript -e 'datablinder::blind_file("patients.csv")'` works everywhere
as soon as the package does. This is for people who blind files often
enough to want a shorter command.

The default `dir` is the first of `~/.local/bin`, `~/bin` and
`/usr/local/bin` that is already on the `PATH` and writable, or
`~/.local/bin` if none of them is. On Windows it is a `datablinder\bin`
folder under `LOCALAPPDATA`. Missing directories are created. A message
says whether the shell will find the command where it landed, and what
to do if it will not.

The command is a copy, but it holds no logic: it calls the installed
package, so upgrading `datablinder` upgrades the command too. Run this
again after upgrading R itself, which moves the `Rscript` the Windows
shim points at.

This is the only function in the package that writes a file anywhere
permanent, so it asks before it does: it prints the directory and waits
for `y`. Any other answer writes nothing, not even the directory. Called
where there is nobody to ask, in a script or `Rscript -e`, it is an
error rather than a silent write to your home directory. A `dir` inside
[`tempdir()`](https://rdrr.io/r/base/tempfile.html) is written without
asking, since the session takes it away again.

## See also

[`blind_file()`](https://agallinat.github.io/datablinder/reference/blind_file.md),
which the command calls, and
[`run_app()`](https://agallinat.github.io/datablinder/reference/run_app.md)
for the same job in a browser.

## Examples

``` r
# Into a scratch directory, to show what is written:
dir <- file.path(tempdir(), "bin")
install_cli(dir)
#> The datablinder command is installed in /tmp/RtmpnvMwMe/bin,
#> which is not on your PATH, so the shell will not find it by name yet.
#> It works by its full path right away:
#>   "/tmp/RtmpnvMwMe/bin/datablinder" --help
#> For the short name, add that folder to your PATH:
#>   echo 'export PATH="/tmp/RtmpnvMwMe/bin:$PATH"' >> ~/.zshrc
#>   (~/.bashrc for bash), then open a new terminal and check with:
#>   echo $PATH
list.files(dir)
#> [1] "datablinder"
```
