test_that("mcp_session returns early when not interactive", {
  local_mocked_bindings(interactive = function() FALSE)
  expect_invisible(mcp_session())
})

test_that("mcp_session initializes appropriate globals", {
  local_mocked_bindings(interactive = function() TRUE)
  mcp_session()
  expect_s3_class(the$session_socket, "nanoSocket")
  expect_type(the$session, "integer")
})

test_that("as_tool_call_result handles normal results", {
  data <- list(id = 1)
  result <- "test result"

  output <- as_tool_call_result(data, result)

  expect_equal(output$jsonrpc, "2.0")
  expect_equal(output$id, 1)
  expect_equal(output$result$content[[1]]$type, "text")
  expect_equal(output$result$content[[1]]$text, "test result")
  expect_false(output$result$isError)
})

test_that("as_tool_call_result handles ContentToolResult with value", {
  data <- list(id = 1)

  tool_result <- ellmer::ContentToolResult(value = "success result")

  output <- as_tool_call_result(data, tool_result)

  expect_equal(output$result$content[[1]]$text, "success result")
  expect_false(output$result$isError)
})

test_that("as_tool_call_result handles ContentToolResult with error", {
  data <- list(id = 1)

  tool_result <- ellmer::ContentToolResult(error = "error message")

  output <- as_tool_call_result(data, tool_result)

  expect_equal(output$result$content[[1]]$text, "error message")
  expect_true(output$result$isError)
})

test_that("as_tool_call_result handles vector results", {
  data <- list(id = 1)
  result <- c("line1", "line2", "line3")

  output <- as_tool_call_result(data, result)

  expect_equal(output$result$content[[1]]$text, "line1\nline2\nline3")
  expect_false(output$result$isError)
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

test_that("infer_ide identifies different IDEs", {
  local_mocked_bindings(commandArgs = function() c("ark", "other", "args"))
  expect_equal(infer_ide(), "Positron")

  local_mocked_bindings(commandArgs = function() c("RStudio", "other", "args"))
  expect_equal(infer_ide(), "RStudio")

  local_mocked_bindings(commandArgs = function() {
    c("unknown-ide", "other", "args")
  })
  expect_equal(infer_ide(), "unknown-ide")
})
