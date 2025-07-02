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
