test_that("roundtrip mcp_server and mcp_tools", {
  previous_server_processes <- names(the$server_processes)

  # example-config configures `Rscript -e "mcptools::mcp_server()"`
  example_config <- readLines(system.file(
    "example-config.json",
    package = "mcptools"
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

test_that("first_responsive_session skips busy sessions", {
  skip_on_cran()
  skip_if(
    length(list_r_sessions()) > 0,
    "Active sessions present; will not tamper with them."
  )
  skip_on_cran()

  busy <- processx::process$new(
    rscript_binary(),
    c("-e", "mcptools::mcp_session();Sys.sleep(1000)"),
    stdout = "|",
    stderr = "|"
  )
  withr::defer(busy$kill())
  Sys.sleep(1)

  available <- processx::process$new(
    rscript_binary(),
    c(
      "-e",
      paste(
        "mcptools::mcp_session();",
        "while(TRUE) {later::run_now();Sys.sleep(0.01)}"
      )
    ),
    stdout = "|",
    stderr = "|"
  )
  withr::defer(available$kill())
  Sys.sleep(1)

  expect_equal(first_responsive_session(), 2)
})
