# A scratch file path for output written during tests.
tmp_path <- function(name) {
  file.path(tempdir(), name)
}

# The class of every column, one per column, for shape comparisons.
col_classes <- function(x) {
  vapply(x, function(column) class(column)[[1]], character(1))
}

file_bytes <- function(path) {
  readBin(path, what = "raw", n = file.size(path))
}
