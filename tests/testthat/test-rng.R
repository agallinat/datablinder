test_that("the session's RNG state is put back", {
  set.seed(99)
  runif(1)
  before <- .Random.seed

  db_with_seed(1, runif(100))

  expect_identical(.Random.seed, before)
})

test_that("a session that had never used the RNG is left without a seed", {
  if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) {
    rm(".Random.seed", envir = globalenv())
  }
  db_with_seed(1, runif(10))
  expect_false(exists(".Random.seed", envir = globalenv(), inherits = FALSE))
})

test_that("the RNG state is put back even when the code fails", {
  set.seed(7)
  before <- .Random.seed
  expect_error(db_with_seed(1, stop("no")), "no")
  expect_identical(.Random.seed, before)
})

test_that("the same seed gives the same numbers", {
  expect_identical(db_with_seed(42, runif(20)), db_with_seed(42, runif(20)))
  expect_false(identical(db_with_seed(42, runif(20)), db_with_seed(43, runif(20))))
})

test_that("no seed gives different numbers each time", {
  first <- db_with_seed(NULL, runif(20))
  second <- db_with_seed(NULL, runif(20))
  expect_false(identical(first, second))
})

test_that("picking a seed without one never asks the RNG", {
  set.seed(5)
  before <- .Random.seed
  db_random_seed()
  expect_identical(.Random.seed, before)
})

test_that("a seed that is not a single number is refused", {
  expect_error(db_with_seed("abc", 1), "single number")
  expect_error(db_with_seed(c(1, 2), 1), "single number")
  expect_error(db_with_seed(NA, 1), "single number")
})

test_that("db_sample_from draws from the values, not from 1..n", {
  # sample(5, 3, replace = TRUE) would draw from 1:5 instead of returning 5
  drawn <- db_with_seed(1, db_sample_from(5, 100))
  expect_true(all(drawn == 5))

  drawn <- db_with_seed(1, db_sample_from(c(10, 20), 100, prob = c(1, 0)))
  expect_true(all(drawn == 10))
})

test_that("db_shuffle keeps every value exactly once", {
  values <- letters[1:10]
  expect_setequal(db_with_seed(1, db_shuffle(values)), values)
})
