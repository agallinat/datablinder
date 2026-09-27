# One blinder per detected type.
#
# Every blinder takes the real column and the number of rows wanted, and returns
# a column of that length with the same class and no real values in it. None of
# them handles missing values: db_blind_column() does that once, at the end, so
# that the rule "keep the share of missing values" is written down in one place.
#
# This file knows nothing about file formats. It must be called inside
# db_with_seed(), as every function here draws random numbers.

# Constants -------------------------------------------------------------

# Points on the inverse CDF used to copy the shape of a continuous column, and
# how much of one gap between them the monotone noise may move a point.
DB_QUANTILE_POINTS <- 50L
DB_QUANTILE_NOISE <- 0.5

# How far the smallest and largest value move, as a share of the range, so that
# the blinded extremes are not the real ones.
DB_SHIFT_MIN <- 0.01
DB_SHIFT_MAX <- 0.05

# Decimal places are copied from the real column, up to this many.
DB_MAX_DECIMALS <- 10L

# Range to spread dates over when every real date is the same, in days.
DB_DATE_FALLBACK_DAYS <- 30

# Distinct values of a shape are drawn by picking distinct positions in the
# space of all values of that shape, which works however full the space is. Past
# this size the space is too big to index, and drawing at random and dropping
# duplicates is both cheap and safe, since there is room to spare.
DB_SHAPE_INDEX_MAX <- 2^31 - 1

# Tries allowed when that fallback is used, and how many extra to ask for each
# time.
DB_UNIQUE_TRIES <- 50L
DB_UNIQUE_MARGIN <- 16L

# Free text is built from these, and never gets longer than this many words.
DB_PLACEHOLDER_WORDS <- c(
  "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel",
  "india", "juliet", "kilo", "lima", "mike", "november", "oscar", "papa",
  "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey",
  "xray", "yankee", "zulu"
)
DB_MAX_PLACEHOLDER_WORDS <- 50L

# Dispatch --------------------------------------------------------------

#' Blind one column
#'
#' @param x The real column.
#' @param spec The spec from `db_detect()`.
#' @param n Number of rows wanted.
#' @param keep_labels Keep real category labels?
#' @param name The column's name, used only in error messages.
#' @return A column of length `n`, same class as `x`.
#' @noRd
db_blind_column <- function(x, spec, n = length(x), keep_labels = FALSE,
                            name = "") {
  # Values are made for the rows that will hold one, not for all n, so that
  # blanking some of them afterwards cannot undo a promise such as "the same set
  # of discrete values".
  missing <- round(n * db_na_share(x))
  present <- n - missing
  if (present <= 0L) {
    return(db_blind_all_na(x, n))
  }
  blinded <- switch(spec$type,
    all_na = db_blind_all_na(x, present),
    constant = db_blind_constant(x, present, keep_labels),
    logical = db_blind_logical(x, present),
    factor = db_blind_factor(x, present, keep_labels),
    labelled = db_blind_labelled(x, present, keep_labels),
    date = db_blind_date(x, present),
    date_text = db_blind_date_text(x, present, spec$format),
    numeric_discrete = db_blind_discrete(x, present),
    numeric_continuous = db_blind_continuous(x, present),
    identifier = db_blind_identifier(x, present),
    email = db_blind_email(x, present),
    url = db_blind_url(x, present),
    phone = db_blind_phone(x, present),
    category_text = db_blind_category(x, present, keep_labels),
    shaped_text = db_blind_shaped(x, present),
    free_text = db_blind_free_text(x, present),
    stop(
      "Column \"", name, "\" is of a type datablinder cannot blind",
      " (", class(x)[[1]], ").",
      call. = FALSE
    )
  )
  db_place_missing(db_keep_attributes(blinded, x), n, missing)
}

# Variable labels and SPSS or Stata display formats travel with the column.
# blind_names is what removes labels, not blinding itself. Anything a blinder has
# already set, such as the relabelled value labels, is left alone.
DB_KEPT_ATTRIBUTES <- c(
  "label", "labels", "format.spss", "format.stata", "display_width"
)

db_keep_attributes <- function(blinded, x) {
  for (name in DB_KEPT_ATTRIBUTES) {
    if (is.null(attr(blinded, name)) && !is.null(attr(x, name))) {
      attr(blinded, name) <- attr(x, name)
    }
  }
  blinded
}

# Spread the blinded values over n rows, leaving `missing` of them empty. The
# share of missing values is kept; which rows are missing is not, as the pattern
# of missingness is itself information about the real data.
db_place_missing <- function(blinded, n, missing) {
  if (missing == 0L) {
    return(blinded)
  }
  # Indexing with NA gives an empty column of the right class, keeping factor
  # levels, value labels and time zones.
  out <- blinded[rep(NA_integer_, n)]
  out[db_shuffle(seq_len(n))[seq_len(n - missing)]] <- blinded
  out
}

# Degenerate columns ----------------------------------------------------

# Indexing with NA gives NA of the right class, keeping factor levels, value
# labels and time zones.
db_blind_all_na <- function(x, n) {
  x[rep(NA_integer_, n)]
}

db_blind_constant <- function(x, n, keep_labels) {
  value <- db_present(x)[[1L]]
  if (is.character(x) && !keep_labels) {
    value <- db_fake_shaped(db_common_shape(db_present(x)), 1L)
  }
  rep(value, n)
}

# Logicals and categories -----------------------------------------------

db_blind_logical <- function(x, n) {
  stats::runif(n) < mean(db_present(x))
}

db_blind_factor <- function(x, n, keep_labels) {
  original <- levels(x)
  labels <- if (keep_labels) original else db_level_labels(length(original))
  counts <- tabulate(match(as.character(db_present(x)), original),
    nbins = length(original)
  )
  drawn <- db_sample_from(labels, n, prob = db_usable_prob(counts))
  # Unused levels stay levels, so nlevels() and the order do not change.
  factor(drawn, levels = labels, ordered = is.ordered(x))
}

db_blind_category <- function(x, n, keep_labels) {
  values <- db_present(as.character(x))
  original <- sort(unique(values))
  labels <- if (keep_labels) original else db_level_labels(length(original))
  counts <- tabulate(match(values, original), nbins = length(original))
  db_sample_covering(labels, n, prob = counts)
}

# SPSS and Stata value labels. The codes are kept, as code written against the
# blinded file will compare against them; only the labels are replaced.
db_blind_labelled <- function(x, n, keep_labels) {
  codes <- db_bare(x)
  present <- db_present(codes)

  # A labelled column is normally categorical, but SPSS files also use labels
  # for a handful of special values on an otherwise continuous variable.
  # Resampling those codes would put real values in the output.
  distinct <- unique(present)
  drawn <- if (is.numeric(present) && length(distinct) > DB_MAX_DISCRETE_VALUES) {
    db_draw_from_quantiles(present, n)
  } else {
    db_sample_from(distinct, n, prob = tabulate(match(present, distinct)))
  }
  if (is.integer(codes)) {
    drawn <- as.integer(round(drawn))
  }

  attributes(drawn) <- attributes(x)[names(attributes(x)) != "names"]
  labels <- attr(x, "labels")
  if (!keep_labels && !is.null(labels)) {
    names(labels) <- db_level_labels(length(labels))
    attr(drawn, "labels") <- labels
  }
  drawn
}

# Numbers ---------------------------------------------------------------

# Same set of values, similar proportions. This is what keeps 0/1 columns 0/1
# and whole numbers whole.
db_blind_discrete <- function(x, n) {
  values <- db_present(as.numeric(x))
  distinct <- unique(values)
  drawn <- db_sample_covering(distinct, n, prob = tabulate(match(values, distinct)))
  db_match_numeric_class(drawn, x)
}

db_blind_continuous <- function(x, n) {
  values <- db_present(as.numeric(x))
  decimals <- db_decimals(values)
  zeros <- round(n * mean(values == 0))

  # Zeros are often structural (no dose, no income), so they are put back as a
  # share rather than left to the interpolation.
  model <- values[values != 0]
  if (length(model) == 0L) {
    model <- values
  }
  drawn <- round(db_draw_from_quantiles(model, n), decimals)
  drawn <- db_keep_sign(drawn, values, decimals)
  if (zeros > 0L) {
    drawn[sample.int(n, zeros)] <- 0
  }
  db_match_numeric_class(drawn, x)
}

# Draw from a smoothed inverse CDF of the real values: quantiles at evenly
# spaced probabilities, moved a little and kept in order, with the two ends
# shifted so the blinded minimum and maximum are not the real ones.
db_draw_from_quantiles <- function(values, n) {
  probs <- seq(0, 1, length.out = DB_QUANTILE_POINTS)
  knots <- stats::quantile(values, probs, names = FALSE)

  span <- knots[[length(knots)]] - knots[[1L]]
  if (span <= 0) {
    span <- max(abs(knots[[1L]]), 1)
  }
  gap <- span / (DB_QUANTILE_POINTS - 1L)
  noise <- stats::runif(length(knots), -DB_QUANTILE_NOISE, DB_QUANTILE_NOISE)
  knots <- sort(knots + noise * gap)

  knots[[1L]] <- knots[[1L]] + db_shift(span)
  knots[[length(knots)]] <- knots[[length(knots)]] + db_shift(span)
  knots <- sort(knots)

  stats::approx(probs, knots, xout = stats::runif(n), rule = 2)$y
}

# A move of 1% to 5% of the range, in either direction.
db_shift <- function(span) {
  size <- stats::runif(1L, DB_SHIFT_MIN, DB_SHIFT_MAX)
  span * size * db_sample_from(c(-1, 1), 1L)
}

# A column of positive numbers must stay positive, and a column with no exact
# zeros must not gain any.
db_keep_sign <- function(drawn, values, decimals) {
  step <- 10^(-decimals)
  has_zero <- any(values == 0)
  if (min(values) >= 0) {
    drawn <- pmax(drawn, if (has_zero) 0 else step)
  }
  if (max(values) <= 0) {
    drawn <- pmin(drawn, if (has_zero) 0 else -step)
  }
  if (!has_zero) {
    drawn[drawn == 0] <- if (min(values) > 0) step else -step
  }
  drawn
}

db_match_numeric_class <- function(drawn, x) {
  if (is.integer(x)) {
    drawn <- as.integer(round(drawn))
  }
  if (!is.null(oldClass(x))) {
    oldClass(drawn) <- oldClass(x)
  }
  drawn
}

# The number of decimal places to copy. format() gives every value the same
# number of decimals, which is the maximum, which is what we want.
db_decimals <- function(values) {
  text <- format(db_even_sample(values), scientific = FALSE, trim = TRUE, digits = 15L)
  decimals <- ifelse(
    grepl(".", text, fixed = TRUE),
    nchar(sub("^.*\\.", "", text)),
    0L
  )
  min(max(decimals), DB_MAX_DECIMALS)
}

# Dates -----------------------------------------------------------------

db_blind_date <- function(x, n) {
  values <- as.numeric(db_present(x))
  span <- diff(range(values))
  if (span == 0) {
    span <- db_date_fallback_span(x)
  }
  low <- min(values) + db_shift(span)
  high <- max(values) + db_shift(span)
  if (high <= low) {
    middle <- (low + high) / 2
    low <- middle - span / 2
    high <- middle + span / 2
  }
  db_match_time_class(stats::runif(n, low, high), x)
}

# Dates written as text stay text, in the format they were written in.
db_blind_date_text <- function(x, n, format) {
  parsed <- suppressWarnings(as.Date(db_present(x), format = format))
  parsed <- parsed[!is.na(parsed)]
  if (length(parsed) == 0L) {
    return(db_blind_shaped(x, n))
  }
  format(db_blind_date(parsed, n), format)
}

db_date_fallback_span <- function(x) {
  if (inherits(x, "POSIXct")) DB_DATE_FALLBACK_DAYS * 86400 else DB_DATE_FALLBACK_DAYS
}

db_match_time_class <- function(drawn, x) {
  if (inherits(x, "POSIXct")) {
    return(structure(drawn, class = oldClass(x), tzone = attr(x, "tzone")))
  }
  days <- round(drawn)
  # IDate stores whole days as an integer
  if (inherits(x, "IDate")) {
    days <- as.integer(days)
  }
  structure(days, class = oldClass(x))
}

# Identifiers, patterns and shapes ---------------------------------------

db_blind_identifier <- function(x, n) {
  if (is.numeric(x)) {
    values <- db_present(as.numeric(x))
    drawn <- db_blind_grouped(values, n, function(k, room) {
      db_distinct_number(values, k, room)
    })
    return(db_match_numeric_class(drawn, x))
  }
  db_blind_shaped(x, n)
}

# New strings with letters, digits and punctuation in the same positions. Also
# used for text identifiers: keeping the number of distinct values, and roughly
# the number of rows per value, is what keeps grouping and joining code working.
db_blind_shaped <- function(x, n) {
  values <- db_present(as.character(x))
  shape <- db_common_shape(values)
  db_blind_grouped(values, n, function(k, room) db_distinct_shaped(shape, k, room))
}

db_blind_email <- function(x, n) {
  db_blind_grouped(db_present(as.character(x)), n, function(k, room) {
    paste0("user_", db_distinct_shaped("aa99", k, room), "@example.com")
  })
}

db_blind_url <- function(x, n) {
  values <- db_present(as.character(x))
  prefix <- if (mean(grepl("^www\\.", values)) > 0.5) "www." else "https://"
  db_blind_grouped(values, n, function(k, room) {
    paste0(prefix, "example.com/", db_distinct_shaped("aaaa", k, room))
  })
}

db_blind_phone <- function(x, n) {
  values <- db_present(as.character(x))
  shape <- db_common_shape(values)
  db_blind_grouped(values, n, function(k, room) db_distinct_shaped(shape, k, room))
}

# Draw as many distinct new values as the real column had, scaled to the number
# of rows wanted, then hand them out with similar group sizes.
#
# `generate(k, room)` must return k distinct values, from a space with room for
# `room` more besides: the new values have to avoid the real ones as well as
# each other, and a space only just big enough cannot do both.
db_blind_grouped <- function(values, n, generate) {
  distinct <- unique(values)
  counts <- tabulate(match(values, distinct))
  # The ratio comes first: a million distinct values times a million rows
  # overflows an integer and gives NA.
  wanted <- min(n, max(1L, round(length(distinct) * (n / length(values)))))

  new_values <- db_avoiding(generate, wanted, distinct)
  if (wanted == n) {
    return(db_shuffle(new_values))
  }
  prob <- if (wanted == length(counts)) counts else db_sample_from(counts, wanted)
  db_sample_covering(new_values, n, prob = db_usable_prob(prob))
}

# k distinct values, none of them a real one. Without this a million identifiers
# drawn from a shape that a million real identifiers already live in collide
# with about four thousand of them, and SPEC.md section 6 makes any overlap on an
# identifier a hard failure.
db_avoiding <- function(generate, k, avoid) {
  room <- length(avoid)
  drawn <- setdiff(generate(k, room), avoid)
  attempt <- 1L
  while (length(drawn) < k && attempt < DB_UNIQUE_TRIES) {
    extra <- generate(k - length(drawn) + DB_UNIQUE_MARGIN, room)
    drawn <- c(drawn, setdiff(extra, c(avoid, drawn)))
    attempt <- attempt + 1L
  }
  if (length(drawn) < k) {
    stop("Could not draw ", k, " distinct values that avoid the real ones.",
      call. = FALSE
    )
  }
  drawn[seq_len(k)]
}

# k distinct values of a shape.
#
# Drawing at random and dropping duplicates fails exactly when it matters most:
# a million rows of five-digit postcodes need about 99,000 distinct codes out of
# the 100,000 that exist, and no amount of retrying will collect them. So the
# k values are chosen as k distinct positions in the space of all values of the
# shape, and each position is then spelled out.
db_distinct_shaped <- function(shape, k, room = 0L) {
  shape <- db_widen_shape(shape, k + room)
  positions <- strsplit(shape, "", fixed = TRUE)[[1]]
  pools <- lapply(positions, db_shape_pool)
  varies <- which(!vapply(pools, is.null, logical(1)))
  sizes <- vapply(pools[varies], length, integer(1))
  capacity <- prod(sizes)

  if (capacity > DB_SHAPE_INDEX_MAX) {
    return(db_unique_values(function(m) db_fake_shaped(shape, m), k))
  }

  place <- sample.int(capacity, k) - 1L
  columns <- as.list(positions)
  for (i in seq_along(varies)) {
    columns[[varies[[i]]]] <- pools[[varies[[i]]]][place %% sizes[[i]] + 1L]
    place <- place %/% sizes[[i]]
  }
  do.call(paste0, columns)
}

# Used only when the space of a shape is too large to index, and so large that
# duplicates are rare.
db_unique_values <- function(generate, k) {
  drawn <- unique(generate(k))
  attempt <- 1L
  while (length(drawn) < k && attempt < DB_UNIQUE_TRIES) {
    drawn <- unique(c(drawn, generate(k - length(drawn) + DB_UNIQUE_MARGIN)))
    attempt <- attempt + 1L
  }
  if (length(drawn) < k) {
    stop("Could not draw ", k, " distinct values of the required shape.",
      call. = FALSE
    )
  }
  drawn[seq_len(k)]
}

# "A-999999" -> one new value per call, letters where letters were, digits where
# digits were, everything else left alone. Values may repeat.
db_fake_shaped <- function(shape, k) {
  positions <- strsplit(shape, "", fixed = TRUE)[[1]]
  if (length(positions) == 0L) {
    return(rep("", k))
  }
  columns <- lapply(positions, function(position) {
    pool <- db_shape_pool(position)
    if (is.null(pool)) rep(position, k) else db_sample_from(pool, k)
  })
  do.call(paste0, columns)
}

db_shape_pool <- function(position) {
  switch(position, A = LETTERS, a = letters, "9" = as.character(0:9), NULL)
}

# How many distinct values a shape can make. Inf once the shape is long enough
# that the product overflows, which is the answer we want anyway.
db_shape_capacity <- function(shape) {
  positions <- strsplit(shape, "", fixed = TRUE)[[1]]
  choices <- vapply(positions, function(position) {
    pool <- db_shape_pool(position)
    if (is.null(pool)) 1 else length(pool)
  }, numeric(1))
  prod(choices)
}

# Only bites on degenerate input, such as a thousand rows of single-letter
# identifiers: better a slightly longer code than a hard failure.
db_widen_shape <- function(shape, k) {
  while (db_shape_capacity(shape) < k) {
    shape <- paste0(shape, "9")
  }
  shape
}

db_common_shape <- function(values) {
  shapes <- table(db_shape(db_even_sample(values)))
  names(shapes)[[which.max(shapes)]]
}

# k distinct numbers with as many digits as the real ones had, chosen the same
# way as shaped values: distinct positions in the range of numbers that width.
db_distinct_number <- function(values, k, room = 0L) {
  sample <- db_even_sample(values)
  digits <- max(nchar(format(abs(sample), scientific = FALSE, trim = TRUE)))
  while (10^digits - 10^(digits - 1L) < k + room) {
    digits <- digits + 1L
  }
  low <- 10^(digits - 1L)
  capacity <- 10^digits - low
  if (capacity > DB_SHAPE_INDEX_MAX) {
    return(db_unique_values(function(m) round(stats::runif(m, low, low + capacity)), k))
  }
  low + sample.int(capacity, k) - 1L
}

# Free text -------------------------------------------------------------

# Placeholder words, as many per row as the real column had, built one word
# count at a time so that a million rows do not mean a million paste() calls.
db_blind_free_text <- function(x, n) {
  values <- db_present(as.character(x))
  lengths <- pmin(db_word_count(db_even_sample(values)), DB_MAX_PLACEHOLDER_WORDS)
  wanted <- db_sample_from(pmax(lengths, 1L), n)

  drawn <- character(n)
  for (count in unique(wanted)) {
    rows <- which(wanted == count)
    words <- replicate(
      count,
      db_sample_from(DB_PLACEHOLDER_WORDS, length(rows)),
      simplify = FALSE
    )
    drawn[rows] <- do.call(paste, words)
  }
  drawn
}

# Small helpers ---------------------------------------------------------

db_level_labels <- function(k) {
  if (k <= 0L) {
    return(character())
  }
  labels <- LETTERS
  suffix <- LETTERS
  while (length(labels) < k) {
    suffix <- as.vector(t(outer(suffix, LETTERS, paste0)))
    labels <- c(labels, suffix)
  }
  labels[seq_len(k)]
}

# The share of values that are missing. An SPSS column can declare codes such as
# 99 as user-missing, and is.na() then reports them as missing; they are codes,
# kept like any other code, so they are counted here as present.
db_na_share <- function(x) {
  if (inherits(x, "haven_labelled_spss")) {
    x <- db_bare(x)
  }
  if (length(x) == 0L) 0 else mean(is.na(x))
}

# The values without any attributes, for a labelled column.
db_bare <- function(x) {
  bare <- unclass(x)
  attributes(bare) <- NULL
  bare
}

# sample() refuses probabilities that are all zero, which happens when every
# value of a factor column is missing.
db_usable_prob <- function(counts) {
  if (sum(counts) == 0) rep(1, length(counts)) else counts
}
