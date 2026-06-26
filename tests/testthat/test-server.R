skip_if(is_fedora())

local_inproc_url <- function() {
  paste0(
    "inproc://mcptools-",
    paste(sample(c(letters, 0:9), 10, replace = TRUE), collapse = "")
  )
}

local_http_post_request <- function(body, ...) {
  c(
    list(
      REQUEST_METHOD = "POST",
      rook.input = list(read = function() charToRaw(to_json(body)))
    ),
    list(...)
  )
}

test_that("roundtrip mcp_server and mcp_tools (stdio)", {
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

test_that("roundtrip mcp_server and mcp_tools (http)", {
  skip_on_cran()
  skip_on_ci()

  port <- httpuv::randomPort()
  http_server <- processx::process$new(
    command = rscript_binary(),
    args = c(
      "-e",
      sprintf("mcptools::mcp_server(type = 'http', port = %d)", port)
    ),
    stdout = "|",
    stderr = "|"
  )
  withr::defer(http_server$kill())

  Sys.sleep(2)

  if (!http_server$is_alive()) {
    stop("HTTP server failed to start")
  }

  config_file <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(
    list(mcpServers = list(mcptools = list(
      url = sprintf("http://127.0.0.1:%d", port)
    ))),
    config_file,
    auto_unbox = TRUE
  )

  tools <- mcp_tools(config_file)

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

test_that("HTTP GET reports unsupported SSE transport", {
  res <- handle_http_request(list(REQUEST_METHOD = "GET"))

  expect_equal(res$status, 405L)
  expect_equal(res$headers$Allow, "POST")
  expect_match(res$body, "HTTP GET/SSE is not supported", fixed = TRUE)
})

test_that("stdio invalid requests return after reporting the error", {
  responses <- list()
  testthat::local_mocked_bindings(
    cat_json = function(x) {
      responses[[length(responses) + 1L]] <<- x
    }
  )

  expect_no_error(handle_message_from_client('{"jsonrpc":"2.0","id":1}'))

  expect_length(responses, 1)
  expect_equal(responses[[1]]$id, 1)
  expect_equal(responses[[1]]$error$code, -32600)
  expect_equal(responses[[1]]$error$message, "Invalid Request")
})

test_that("HTTP requests reject unsupported MCP-Protocol-Version headers", {
  res <- handle_http_request(list(
    REQUEST_METHOD = "GET",
    HTTP_MCP_PROTOCOL_VERSION = "2099-01-01"
  ))

  expect_equal(res$status, 400L)
  expect_match(res$body, "Invalid or unsupported MCP-Protocol-Version")
})

test_that("HTTP tools/list honors MCP-Protocol-Version header", {
  old_server_tools <- the$server_tools
  withr::defer(the$server_tools <- old_server_tools)
  local_protocol_version("2025-11-25")

  tool <- ellmer::tool(
    function() "ok",
    "Read project state",
    name = "read_project",
    annotations = ellmer::tool_annotations(title = "Read Project")
  )
  set_server_tools(list(tool), session_tools = FALSE)

  res <- handle_http_request(local_http_post_request(
    list(
      jsonrpc = "2.0",
      id = 1,
      method = "tools/list"
    ),
    HTTP_MCP_PROTOCOL_VERSION = "2025-03-26"
  ))
  body <- jsonlite::parse_json(res$body)
  tool <- body$result$tools[[1]]

  expect_equal(res$status, 200L)
  expect_false("title" %in% names(tool))
  expect_equal(tool$annotations$title, "Read Project")
})

test_that("HTTP tools/call honors MCP-Protocol-Version header", {
  old_server_tools <- the$server_tools
  old_sessions_enabled <- the$sessions_enabled
  withr::defer({
    the$server_tools <- old_server_tools
    the$sessions_enabled <- old_sessions_enabled
  })
  local_protocol_version("2025-11-25")

  tool <- ellmer::tool(
    function() list(auc = 0.92),
    "Return metrics",
    name = "metrics"
  )
  set_server_tools(list(tool), session_tools = FALSE)
  the$sessions_enabled <- FALSE

  res <- handle_http_request(local_http_post_request(
    list(
      jsonrpc = "2.0",
      id = 1,
      method = "tools/call",
      params = list(name = "metrics", arguments = list())
    ),
    HTTP_MCP_PROTOCOL_VERSION = "2025-03-26"
  ))
  body <- jsonlite::parse_json(res$body)

  expect_equal(res$status, 200L)
  expect_null(body$result$structuredContent)
  expect_equal(body$result$content[[1]]$text, "0.92")
})

test_that("HTTP missing MCP-Protocol-Version does not inherit global state", {
  old_server_tools <- the$server_tools
  withr::defer(the$server_tools <- old_server_tools)
  local_protocol_version()

  tool <- ellmer::tool(
    function() "ok",
    "Read project state",
    name = "read_project",
    annotations = ellmer::tool_annotations(title = "Read Project")
  )
  set_server_tools(list(tool), session_tools = FALSE)

  handle_http_request(local_http_post_request(list(
    jsonrpc = "2.0",
    id = 1,
    method = "initialize",
    params = list(protocolVersion = "2025-11-25")
  )))

  res <- handle_http_request(local_http_post_request(list(
    jsonrpc = "2.0",
    id = 2,
    method = "tools/list"
  )))
  body <- jsonlite::parse_json(res$body)
  tool <- body$result$tools[[1]]

  expect_equal(the$protocol_version, "2025-11-25")
  expect_equal(res$status, 200L)
  expect_false("title" %in% names(tool))
  expect_equal(tool$annotations$title, "Read Project")
})

test_that("HTTP requests validate Connect shared secret when configured", {
  withr::local_options(plumber2.sharedSecret = "secret")

  expect_equal(
    handle_http_request(list(REQUEST_METHOD = "GET"))$status,
    403L
  )
  expect_equal(
    handle_http_request(list(
      REQUEST_METHOD = "GET",
      HTTP_PLUMBER_SHARED_SECRET = "wrong"
    ))$status,
    403L
  )
  expect_equal(
    handle_http_request(list(
      REQUEST_METHOD = "GET",
      HTTP_PLUMBER_SHARED_SECRET = "secret"
    ))$status,
    405L
  )
})

test_that("HTTP shared secret ignores empty override", {
  withr::local_options(
    mcptools.http_shared_secret = "",
    plumber2.sharedSecret = "secret"
  )

  expect_equal(
    handle_http_request(list(REQUEST_METHOD = "GET"))$status,
    403L
  )
  expect_equal(
    handle_http_request(list(
      REQUEST_METHOD = "GET",
      HTTP_PLUMBER_SHARED_SECRET = "secret"
    ))$status,
    405L
  )
})

test_that("HTTP shared secret uses non-empty mcptools override", {
  withr::local_options(
    mcptools.http_shared_secret = "mcptools-secret",
    plumber2.sharedSecret = "connect-secret"
  )

  expect_equal(
    handle_http_request(list(
      REQUEST_METHOD = "GET",
      HTTP_PLUMBER_SHARED_SECRET = "connect-secret"
    ))$status,
    403L
  )
  expect_equal(
    handle_http_request(list(
      REQUEST_METHOD = "GET",
      HTTP_PLUMBER_SHARED_SECRET = "mcptools-secret"
    ))$status,
    405L
  )
})

test_that("HTTP requests validate configured trusted hosts", {
  local_http_security(trusted_hosts = "127.0.0.1:1234")

  expect_equal(
    handle_http_request(list(REQUEST_METHOD = "GET"))$status,
    403L
  )
  expect_equal(
    handle_http_request(list(
      REQUEST_METHOD = "GET",
      HTTP_HOST = "connect.example.com"
    ))$status,
    403L
  )
  expect_equal(
    handle_http_request(list(
      REQUEST_METHOD = "GET",
      HTTP_HOST = "127.0.0.1:1234"
    ))$status,
    405L
  )
})

test_that("HTTP requests validate configured origins", {
  local_http_security(allowed_origins = "https://connect.example.com")

  expect_equal(
    handle_http_request(list(
      REQUEST_METHOD = "GET",
      HTTP_ORIGIN = "http://localhost:3000"
    ))$status,
    405L
  )
  expect_equal(
    handle_http_request(list(
      REQUEST_METHOD = "GET",
      HTTP_ORIGIN = "https://connect.example.com"
    ))$status,
    405L
  )
  expect_equal(
    handle_http_request(list(
      REQUEST_METHOD = "GET",
      HTTP_ORIGIN = "https://evil.example.com"
    ))$status,
    403L
  )
})

test_that("forward_request returns append_tool_fn errors", {
  old_server_tools <- the$server_tools
  withr::defer(the$server_tools <- old_server_tools)

  set_server_tools(NULL)

  res <- forward_request(list(
    id = 1,
    method = "tools/call",
    params = list(name = "missing_tool", arguments = list())
  ))

  expect_s3_class(res, "jsonrpc_error")
  expect_equal(res$error$message, "Method not found")
})

test_that("forward_request times out when session does not respond", {
  old_socket_url <- the$socket_url
  old_server_socket <- the$server_socket
  old_server_tools <- the$server_tools
  withr::defer({
    nanonext::reap(the$server_socket)
    the$socket_url <- old_socket_url
    the$server_socket <- old_server_socket
    the$server_tools <- old_server_tools
  })

  test_tool <- ellmer::tool(function() "ok", "Test tool", name = "test_tool")
  set_server_tools(list(test_tool), session_tools = FALSE)
  testthat::local_mocked_bindings(session_response_timeout = function() 10L)

  the$socket_url <- local_inproc_url()
  session_socket <- nanonext::socket("poly")
  withr::defer(nanonext::reap(session_socket))
  session_url <- sprintf("%s%d", the$socket_url, 1L)
  expect_identical(nanonext::listen(session_socket, url = session_url), 0L)

  the$server_socket <- nanonext::socket("poly")
  expect_identical(
    nanonext::dial(the$server_socket, url = session_url, autostart = NA),
    0L
  )

  res <- forward_request(list(
    id = 1,
    method = "tools/call",
    params = list(name = "test_tool", arguments = list())
  ))

  expect_equal(res$error$code, -32603)
  expect_match(res$error$message, "Timed out waiting")
})

test_that("forward_request ignores stale responses", {
  old_socket_url <- the$socket_url
  old_server_socket <- the$server_socket
  old_server_tools <- the$server_tools
  withr::defer({
    nanonext::reap(the$server_socket)
    the$socket_url <- old_socket_url
    the$server_socket <- old_server_socket
    the$server_tools <- old_server_tools
  })

  test_tool <- ellmer::tool(function() "ok", "Test tool", name = "test_tool")
  set_server_tools(list(test_tool), session_tools = FALSE)
  testthat::local_mocked_bindings(session_response_timeout = function() 20L)

  the$socket_url <- local_inproc_url()
  session_socket <- nanonext::socket("poly")
  withr::defer(nanonext::reap(session_socket))
  session_url <- sprintf("%s%d", the$socket_url, 1L)
  expect_identical(nanonext::listen(session_socket, url = session_url), 0L)

  the$server_socket <- nanonext::socket("poly")
  expect_identical(
    nanonext::dial(the$server_socket, url = session_url, autostart = NA),
    0L
  )

  expect_identical(
    nanonext::send(
      session_socket,
      to_json(jsonrpc_response(99, result = list(ok = TRUE))),
      mode = "raw"
    ),
    0L
  )

  res <- forward_request(list(
    id = 1,
    method = "tools/call",
    params = list(name = "test_tool", arguments = list())
  ))

  expect_equal(res$error$code, -32603)
  expect_match(res$error$message, "Timed out waiting")
})

test_that("receive_forwarded_response errors for non-object JSON", {
  old_socket_url <- the$socket_url
  old_server_socket <- the$server_socket
  old_server_tools <- the$server_tools
  withr::defer({
    nanonext::reap(the$server_socket)
    the$socket_url <- old_socket_url
    the$server_socket <- old_server_socket
    the$server_tools <- old_server_tools
  })

  the$socket_url <- local_inproc_url()
  session_socket <- nanonext::socket("poly")
  withr::defer(nanonext::reap(session_socket))
  session_url <- sprintf("%s%d", the$socket_url, 1L)
  expect_identical(nanonext::listen(session_socket, url = session_url), 0L)

  the$server_socket <- nanonext::socket("poly")
  expect_identical(
    nanonext::dial(the$server_socket, url = session_url, autostart = NA),
    0L
  )

  expect_identical(nanonext::send(session_socket, "\"oops\"", mode = "raw"), 0L)

  res <- receive_forwarded_response(1, 10L)

  expect_equal(res$error$code, -32603)
  expect_match(res$error$message, "invalid response")
})

test_that("session_response_timeout is configurable", {
  withr::local_options(mcptools.session_response_timeout_seconds = NULL)
  withr::local_envvar(MCPTOOLS_SESSION_RESPONSE_TIMEOUT_SECONDS = "2")
  expect_equal(session_response_timeout(), 2000L)

  withr::local_options(mcptools.session_response_timeout_seconds = 1)
  expect_equal(session_response_timeout(), 1000L)

  withr::local_options(mcptools.session_response_timeout_seconds = -1)
  expect_equal(session_response_timeout(), 120000L)
})
