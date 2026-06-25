skip_if(is_fedora())

test_that("read_connect_server_config reads mcptools server config", {
  dir <- withr::local_tempdir()
  tools <- file.path(dir, "tools.R")
  writeLines("list()", tools)

  server_file <- file.path(dir, "_server.yml")
  writeLines(
    c(
      "engine: mcptools",
      "tools: tools.R"
    ),
    server_file
  )

  config <- read_connect_server_config(server_file)

  expect_equal(config$tools, normalizePath(tools))
  expect_false(config$session_tools)
})

test_that("read_connect_server_config allows explicit session tools", {
  dir <- withr::local_tempdir()
  tools <- file.path(dir, "tools.R")
  writeLines("list()", tools)

  server_file <- file.path(dir, "_server.yml")
  writeLines(
    c(
      "engine: mcptools",
      "tools: tools.R",
      "session_tools: true"
    ),
    server_file
  )

  config <- read_connect_server_config(server_file)

  expect_true(config$session_tools)
})

test_that("read_connect_server_config validates server config", {
  dir <- withr::local_tempdir()
  server_file <- file.path(dir, "_server.yml")

  writeLines("engine: plumber2", server_file)
  expect_error(
    read_connect_server_config(server_file),
    "engine: mcptools",
    fixed = TRUE
  )

  writeLines(c("engine: mcptools", "tools: missing.R"), server_file)
  expect_error(
    read_connect_server_config(server_file),
    "does not exist",
    fixed = TRUE
  )

  writeLines(c("engine: mcptools", "session_tools: maybe"), server_file)
  expect_error(
    read_connect_server_config(server_file),
    "session_tools",
    fixed = TRUE
  )
})

test_that("launch_server calls mcp_server with Connect defaults", {
  dir <- withr::local_tempdir()
  tools <- file.path(dir, "tools.R")
  writeLines("list()", tools)

  server_file <- file.path(dir, "_server.yml")
  writeLines(
    c(
      "engine: mcptools",
      "tools: tools.R"
    ),
    server_file
  )

  testthat::local_mocked_bindings(
    mcp_server = function(...) list(...)
  )

  res <- launch_server(settings = server_file, host = "127.0.0.1", port = 1234L)

  expect_equal(res$tools, normalizePath(tools))
  expect_equal(res$type, "http")
  expect_equal(res$host, "127.0.0.1")
  expect_equal(res$port, 1234L)
  expect_false(res$session_tools)
})

test_that("launch_server allows omitted host and port", {
  dir <- withr::local_tempdir()
  tools <- file.path(dir, "tools.R")
  writeLines("list()", tools)

  server_file <- file.path(dir, "_server.yml")
  writeLines(
    c(
      "engine: mcptools",
      "tools: tools.R"
    ),
    server_file
  )

  testthat::local_mocked_bindings(
    mcp_server = function(...) list(...)
  )

  res <- launch_server(settings = server_file, ignored = TRUE)

  expect_equal(res$tools, normalizePath(tools))
  expect_equal(res$type, "http")
  expect_null(res$host)
  expect_null(res$port)
  expect_false(res$session_tools)
})

test_that("launch_server allows Connect origin when configured", {
  dir <- withr::local_tempdir()
  tools <- file.path(dir, "tools.R")
  writeLines("list()", tools)

  server_file <- file.path(dir, "_server.yml")
  writeLines(
    c(
      "engine: mcptools",
      "tools: tools.R"
    ),
    server_file
  )

  withr::local_envvar(CONNECT_SERVER = "https://connect.example.com/rsc")
  local_http_security(allowed_origins = character())
  testthat::local_mocked_bindings(
    mcp_server = function(...) list(...)
  )

  launch_server(settings = server_file, host = "127.0.0.1", port = 1234L)

  expect_equal(the$http_allowed_origins, "https://connect.example.com")
})
