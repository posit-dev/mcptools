test_that("mcp_session returns early when not interactive", {
  local_mocked_bindings(interactive = function() FALSE)
  expect_invisible(mcp_session())
})

test_that("drop_nulls works", {
  # drop_nulls removes NULL values from list
  result <- drop_nulls(list(a = 1, b = NULL, c = "text"))
  expect_equal(result, list(a = 1, c = "text"))
  expect_equal(names(result), c("a", "c"))

  # drop_nulls keeps non-NULL values
  result <- drop_nulls(list(a = 1, b = 2, c = 3))
  expect_equal(result, list(a = 1, b = 2, c = 3))

  # drop_nulls handles empty list
  result <- drop_nulls(list())
  expect_equal(result, list())

  # drop_nulls handles list with only NULL values
  result <- drop_nulls(list(a = NULL, b = NULL))
  expect_equal(result, named_list())
  expect_equal(length(result), 0)
})

test_that("describe_session works", {
  the$session <- 42
  local_mocked_bindings(
    basename = function(x) "test-dir",
    getwd = function() "/path/to/test-dir",
    infer_ide = function() "Test IDE"
  )
  result <- describe_session()
  expect_equal(result, "42: test-dir (Test IDE)")
})
