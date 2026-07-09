skip_if(is_fedora())

test_that("mcp_session returns early when not interactive", {
  local_mocked_bindings(interactive = function() FALSE)
  expect_invisible(mcp_session())
})

test_that("mcp_session initializes appropriate globals", {
  local_mocked_bindings(interactive = function() TRUE)
  expect_s3_class(mcp_session(), "nanoSocket")
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

  expect_match(output$result$content[[1]]$text, "error message")
  expect_true(output$result$isError)
})

test_that("as_tool_call_result returns structuredContent for named lists", {
  data <- list(id = 1, protocolVersion = "2025-06-18")
  result <- list(auc = 0.92, tss = 0.81)

  output <- as_tool_call_result(data, result)

  expect_equal(
    output$result$content[[1]],
    list(
      type = "text",
      text = "{\"auc\":0.92,\"tss\":0.81}"
    )
  )
  expect_equal(output$result$structuredContent, result)
  expect_false(output$result$isError)
})

test_that("as_tool_call_result gates structuredContent by protocol version", {
  data <- list(id = 1, protocolVersion = "2025-03-26")
  result <- list(auc = 0.92, tss = 0.81)

  output <- as_tool_call_result(data, result)

  expect_null(output$result$structuredContent)
  expect_equal(output$result$content[[1]]$text, "0.92\n0.81")
  expect_false(output$result$isError)
})

test_that("as_tool_call_result handles ContentToolResult with structured value", {
  data <- list(id = 1, protocolVersion = "2025-06-18")
  result <- ellmer::ContentToolResult(value = list(auc = 0.92))

  output <- as_tool_call_result(data, result)

  expect_equal(
    output$result$content[[1]],
    list(
      type = "text",
      text = "{\"auc\":0.92}"
    )
  )
  expect_equal(output$result$structuredContent, list(auc = 0.92))
  expect_false(output$result$isError)
})

test_that("as_tool_call_result omits structuredContent for tool errors", {
  data <- list(id = 1, protocolVersion = "2025-06-18")
  result <- ellmer::ContentToolResult(error = "bad input")

  output <- as_tool_call_result(data, result)

  expect_null(output$result$structuredContent)
  expect_match(output$result$content[[1]]$text, "bad input")
  expect_true(output$result$isError)
})

test_that("as_tool_call_result handles direct image content", {
  data <- list(id = 1)
  result <- ellmer::ContentImageInline(type = "image/png", data = "abc123")

  output <- as_tool_call_result(data, result)

  expect_equal(output$result$content[[1]]$type, "image")
  expect_equal(output$result$content[[1]]$data, "abc123")
  expect_equal(output$result$content[[1]]$mimeType, "image/png")
  expect_false(output$result$isError)
})

test_that("as_tool_call_result handles ContentToolResult with image content", {
  data <- list(id = 1)
  image <- ellmer::ContentImageInline(type = "image/png", data = "abc123")
  result <- ellmer::ContentToolResult(value = image)

  output <- as_tool_call_result(data, result)

  expect_equal(output$result$content[[1]]$type, "image")
  expect_equal(output$result$content[[1]]$data, "abc123")
  expect_equal(output$result$content[[1]]$mimeType, "image/png")
  expect_false(output$result$isError)
})

test_that("as_tool_call_result inlines remote image content", {
  data <- list(id = 1)
  result <- ellmer::content_image_url("https://example.com/img.png")

  # large enough that MIME-style base64 wrapping would insert newlines
  body <- as.raw(rep(0:255, 4))
  httr2::local_mocked_responses(list(
    httr2::response(
      status_code = 200,
      headers = list("Content-Type" = "image/jpeg"),
      body = body
    )
  ))

  output <- as_tool_call_result(data, result)

  expect_equal(output$result$content[[1]]$type, "image")
  expect_equal(output$result$content[[1]]$mimeType, "image/jpeg")
  expect_false(grepl("\n", output$result$content[[1]]$data))
  expect_equal(jsonlite::base64_dec(output$result$content[[1]]$data), body)
  expect_false(output$result$isError)
})

test_that("as_tool_call_result surfaces remote image fetch failures", {
  data <- list(id = 1)
  result <- ellmer::content_image_url("https://example.com/missing.png")

  httr2::local_mocked_responses(list(httr2::response(status_code = 404)))

  expect_error(
    as_tool_call_result(data, result),
    "Failed to fetch remote image content"
  )
})

test_that("as_tool_call_result handles bare mixed content", {
  data <- list(id = 1)
  image <- ellmer::ContentImageInline(type = "image/png", data = "abc123")
  result <- list("caption", image)

  output <- as_tool_call_result(data, result)

  expect_equal(
    output$result$content[[1]],
    list(type = "text", text = "caption")
  )
  expect_equal(
    output$result$content[[2]],
    list(
      type = "image",
      data = "abc123",
      mimeType = "image/png"
    )
  )
  expect_null(output$result$structuredContent)
  expect_false(output$result$isError)
})

test_that("as_tool_call_result handles mixed ellmer content", {
  data <- list(id = 1)
  text <- ellmer::ContentText(text = "caption")
  image <- ellmer::ContentImageInline(type = "image/png", data = "abc123")
  result <- ellmer::ContentToolResult(value = list(text, image))

  output <- as_tool_call_result(data, result)

  expect_equal(
    output$result$content[[1]],
    list(type = "text", text = "caption")
  )
  expect_equal(
    output$result$content[[2]],
    list(
      type = "image",
      data = "abc123",
      mimeType = "image/png"
    )
  )
  expect_null(output$result$structuredContent)
  expect_false(output$result$isError)
})

test_that("as_tool_call_result handles vector results", {
  data <- list(id = 1)
  result <- c("line1", "line2", "line3")

  output <- as_tool_call_result(data, result)

  expect_equal(output$result$content[[1]]$text, "line1\nline2\nline3")
  expect_false(output$result$isError)
})

test_that("as_tool_call_result omits structuredContent for non-object results", {
  data <- list(id = 1, protocolVersion = "2025-06-18")

  unnamed <- as_tool_call_result(data, list(1, 2))
  frame <- as_tool_call_result(data, data.frame(a = 1:2, b = c("x", "y")))

  expect_null(unnamed$result$structuredContent)
  expect_null(frame$result$structuredContent)
})

test_that("as_tool_call_result preserves names in atomic structured results", {
  data <- list(id = 1, protocolVersion = "2025-06-18")

  output <- as_tool_call_result(data, c(auc = 0.92, tss = 0.81))

  expect_equal(output$result$structuredContent, list(auc = 0.92, tss = 0.81))
  expect_equal(output$result$content[[1]]$text, "{\"auc\":0.92,\"tss\":0.81}")
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
