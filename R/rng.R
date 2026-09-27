# Seeded work that leaves the user's session alone.
#
# Blinding needs a lot of random numbers, and a package has no business
# changing the random stream of the session that called it. Everything random
# happens inside db_with_seed(), which puts .Random.seed back exactly as it
# found it, including the case where the session had not used the RNG at all.

#' Run code with a seed, then put the RNG back
#'
#' @param seed A seed, or `NULL` to pick one without touching the RNG.
#' @param code The code to run.
#' @return Whatever `code` returns.
#' @noRd
db_with_seed <- function(seed, code) {
  restore <- db_rng_snapshot()
  on.exit(restore(), add = TRUE)
  set.seed(db_pick_seed(seed))
  code
}

db_pick_seed <- function(seed) {
  if (is.null(seed)) {
    return(db_random_seed())
  }
  if (length(seed) != 1L || is.na(seed) || !is.numeric(seed)) {
    stop("`seed` must be a single number, or NULL.", call. = FALSE)
  }
  as.integer(seed)
}

# A seed drawn from the clock and the process, never from the RNG: asking the
# RNG for a seed would be the very thing we are trying to avoid. The
# microseconds matter, or two runs in the same second would come out identical.
db_random_seed <- function() {
  now <- as.numeric(Sys.time())
  microseconds <- as.integer((now %% 1) * 1e6)
  seconds <- as.integer(now %% 1e8)
  bitwXor(bitwXor(seconds, microseconds), Sys.getpid())
}

# Returns a function that undoes whatever the RNG does next.
db_rng_snapshot <- function() {
  env <- globalenv()
  if (exists(".Random.seed", envir = env, inherits = FALSE)) {
    state <- get(".Random.seed", envir = env, inherits = FALSE)
    function() assign(".Random.seed", state, envir = env)
  } else {
    # The session had never used the RNG, so leave it with no seed at all.
    function() {
      if (exists(".Random.seed", envir = env, inherits = FALSE)) {
        rm(".Random.seed", envir = env)
      }
    }
  }
}

# Sampling helpers ------------------------------------------------------

# sample(x, ...) means sample.int(x, ...) when x is one number, which would
# quietly draw from 1..x instead of returning x. Every draw in the package goes
# through here instead.
db_sample_from <- function(values, n, prob = NULL) {
  values[sample.int(length(values), n, replace = TRUE, prob = prob)]
}

db_shuffle <- function(values) {
  values[sample.int(length(values))]
}

# Draw n values, but make sure every one of `values` turns up at least once.
# Drawing purely by probability loses rare values: mtcars$carb == 6 appears on
# one row of 32, so a plain draw drops it about a third of the time, and then
# the blinded column has five distinct values where the real one had six.
db_sample_covering <- function(values, n, prob = NULL) {
  if (n <= length(values)) {
    return(db_sample_from(values, n, prob = prob))
  }
  rest <- db_sample_from(values, n - length(values), prob = prob)
  db_shuffle(c(values, rest))
}
