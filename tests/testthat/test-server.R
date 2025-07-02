test_that("roundtrip mcp_server and mcp_tools", {
  previous_server_processes <- names(the$server_processes)

  # example-config configures `Rscript -e "acquaint::mcp_server()"`
  example_config <- readLines(system.file(
    "example-config.json",
    package = "acquaint"
  ))
  example_config <- gsub("Rscript", rscript_binary(), example_config)
  tmp_file <- withr::local_tempfile(fileext = ".json")
  writeLines(example_config, tmp_file)

  tools <- mcp_tools(tmp_file)
  withr::defer(
    the$server_processes[[
      setdiff(names(the$server_processes), previous_server_processes)
    ]]$kill()
  )
  tool_names <- c()
  for (tool in tools) {
    tool_names <- c(tool_names, tool@name)
  }
  expect_true(
    all(c("list_r_sessions", "select_r_session") %in% tool_names)
  )
  list_r_sessions_ <- tools[[which(tool_names == "list_r_sessions")]]
  expect_equal(list_r_sessions_tool@description, list_r_sessions_@description)
})

test_that("check_not_interactive errors informatively", {
  testthat::local_mocked_bindings(interactive = function(...) TRUE)

  expect_snapshot(error = TRUE, mcp_server())
})
