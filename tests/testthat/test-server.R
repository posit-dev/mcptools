test_that("roundtrip mcp_server and mcp_tools", {
  # example-config configures `Rscript -e "acquaint::mcp_server()"`
  previous_server_processes <- names(the$server_processes)

  tools <- mcp_tools(system.file("example-config.json", package = "acquaint"))
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
