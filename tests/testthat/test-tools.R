test_that("set_server_tools sets default tools when x is NULL", {
  set_server_tools(NULL)
  server_tools_names <- vapply(
    the$server_tools,
    function(x) x@name,
    character(1)
  )
  expect_true(all(
    c("list_r_sessions", "select_r_session") %in% server_tools_names
  ))
  expect_equal(length(the$server_tools), 2)
})

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
      package = "mcptools"
    ))
  )
  expect_true("tool_rnorm" %in% names(the$server_tools))
})

test_that("set_server_tools errors informatively", {
  tls <-
    source(
      system.file(
        "example-ellmer-tools.R",
        package = "mcptools"
      ),
      local = TRUE
    )

  # needs to be wrapped in `list()`
  expect_snapshot(set_server_tools(tls$value[[1]]), error = TRUE)

  # select_r_session and list_r_sessions are reserved names
  tls$value[[1]]@name <- "select_r_session"
  expect_snapshot(set_server_tools(list(tls$value[[1]])), error = TRUE)
})

test_that("get_mcptools_tools works", {
  res <- get_mcptools_tools()
  expect_true(all(
    c("list_r_sessions", "select_r_session") %in% names(res)
  ))
})

test_that("get_mcptools_tools_as_json works", {
  res <- get_mcptools_tools_as_json()

  expect_true(all(vapply(
    res,
    function(x) all(c(c("name", "description", "inputSchema")) %in% names(x)),
    logical(1)
  )))
})
