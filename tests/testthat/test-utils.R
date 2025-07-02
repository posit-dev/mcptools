test_that("jsonrpc_response works", {
  # jsonrpc_response returns result when provided
  result <- jsonrpc_response("123", result = "success")
  expect_equal(result$jsonrpc, "2.0")
  expect_equal(result$id, "123")
  expect_equal(result$result, "success")
  expect_null(result$error)

  # jsonrpc_response returns error when provided
  result <- jsonrpc_response(
    "456",
    error = list(code = -32603, message = "Internal error")
  )
  expect_equal(result$jsonrpc, "2.0")
  expect_equal(result$id, "456")
  expect_null(result$result)
  expect_equal(result$error, list(code = -32603, message = "Internal error"))

  # jsonrpc_response warns when both result and error provided
  expect_snapshot(
    .res <- jsonrpc_response(
      "789",
      result = "success",
      error = list(code = -32603, message = "error")
    )
  )

  # jsonrpc_response warns when neither result nor error provided
  expect_snapshot(.res <- jsonrpc_response("000"))
})

test_that("named_list works", {
  # named_list creates named list with arguments
  result <- named_list(a = 1, b = 2)
  expect_equal(result, list(a = 1, b = 2))
  expect_true(is.list(result))
  expect_equal(names(result), c("a", "b"))

  # named_list creates empty named list when no arguments
  result <- named_list()
  expect_equal(result, list(a = 1)[0])
  expect_true(is.list(result))
  expect_equal(length(result), 0)
  expect_true(!is.null(names(result)))
})

test_that("to_json works", {
  # to_json converts list to JSON with auto_unbox
  result <- to_json(list(a = 1, b = "text"))
  expect_true(is.character(result))
  expect_equal(jsonlite::fromJSON(result), list(a = 1, b = "text"))

  # to_json passes additional arguments to jsonlite::toJSON
  result <- to_json(list(a = 1), pretty = TRUE)
  expect_true(grepl("\n", result))

  # to_json handles single values with auto_unbox
  result <- to_json(list(value = 42))
  parsed <- jsonlite::fromJSON(result)
  expect_equal(parsed$value, 42)
  expect_false(is.list(parsed$value))
})

test_that("mcptools_log_file works", {
  # mcptools_log_file returns environment variable when set
  withr::local_envvar(MCPTOOLS_LOG_FILE = "/custom/log/file.txt")
  result <- mcptools_log_file()
  expect_equal(result, "/custom/log/file.txt")

  # mcptools_log_file returns tempfile when environment variable not set
  withr::local_envvar(MCPTOOLS_LOG_FILE = NULL)
  result <- mcptools_log_file()
  expect_true(grepl("\\.txt$", result))
  expect_true(file.exists(dirname(result)))
})
