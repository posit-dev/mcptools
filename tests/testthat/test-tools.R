test_that("set_server_tools can handle `tools` as path", {
  tmp_file <- withr::local_tempfile(fileext = ".r")
  local_mocked_bindings(check_not_interactive = function(...) {})

  # temp file doesn't yet exist
  expect_snapshot(error = TRUE, mcp_server(tmp_file))

  # temp file errors when sourced
  writeLines("boop", tmp_file)
  expect_snapshot(error = TRUE, mcp_server(tmp_file))

  # temp file doesn't return a list of tools
  writeLines("\"boop\"", tmp_file)
  expect_snapshot(error = TRUE, mcp_server(tmp_file))

  expect_no_condition(
    set_server_tools(system.file(
      "example-ellmer-tools.R",
      package = "acquaint"
    ))
  )
  expect_true("tool_rnorm" %in% names(the$server_tools))
})
