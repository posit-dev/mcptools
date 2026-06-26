skip_if(is_fedora())

# config -----------------------------------------------------------------------
test_that("HTTP headers interpolate environment variables", {
  withr::local_envvar(MCPTOOLS_TEST_TOKEN = "secret-token")

  headers <- mcp_config_headers(list(
    Authorization = "Bearer ${MCPTOOLS_TEST_TOKEN}"
  ))

  expect_equal(headers[["Authorization"]], "Bearer secret-token")
})

test_that("HTTP header interpolation errors when environment variables are unset", {
  withr::local_envvar(MCPTOOLS_MISSING_TOKEN = NA)

  expect_error(
    mcp_config_headers(list(Authorization = "Bearer ${MCPTOOLS_MISSING_TOKEN}")),
    "MCPTOOLS_MISSING_TOKEN"
  )
})

test_that("HTTP config reserves protocol-owned headers", {
  for (header in c("Accept", "Content-Type", "MCP-Session-Id", "MCP-Protocol-Version")) {
    headers <- list("manual")
    names(headers) <- header

    expect_error(
      mcp_config_headers(headers),
      "managed by mcptools",
      fixed = TRUE
    )
  }
})

test_that("HTTP config rejects Authorization header alongside OAuth", {
  expect_error(
    mcp_config_headers(
      list(Authorization = "Bearer x"),
      oauth = list(client_info = list(client_id = "id"))
    ),
    "both configure authorization"
  )

  expect_silent(
    mcp_config_headers(
      list(Authorization = "Bearer x"),
      oauth = list(
        client_info = list(client_id = "id"),
        allow_authorization_header = TRUE
      )
    )
  )
})

test_that("credentialed public HTTP endpoints require explicit opt-out", {
  transport <- mcp_transport_http(list(url = "http://example.test/mcp"))
  expect_false(transport$allow_http)

  transport <- mcp_transport_http(list(
    url = "http://127.0.0.1:8080/mcp",
    headers = list("X-Api-Key" = "secret")
  ))
  expect_false(transport$allow_http)

  expect_error(
    mcp_transport_http(list(
      url = "http://example.test/mcp",
      headers = list("X-Api-Key" = "secret")
    )),
    "Credentialed remote MCP endpoints"
  )

  transport <- mcp_transport_http(list(
    url = "http://example.test/mcp",
    allow_http = TRUE,
    headers = list("X-Api-Key" = "secret")
  ))
  expect_true(transport$allow_http)

  expect_error(
    mcp_transport_http(list(
      url = "http://example.test/mcp",
      allow_http = "yes",
      headers = list("X-Api-Key" = "secret")
    )),
    "allow_http"
  )
})

test_that("HTTP transport timeout must be a single positive number", {
  transport <- mcp_transport_http(list(url = "https://example.test/mcp", timeout = 10))
  expect_equal(transport$timeout, 10)

  req <- mcp_transport_http_request(
    transport,
    list(jsonrpc = "2.0", id = 1L, method = "ping")
  )
  expect_equal(req$options$timeout_ms, 10000)

  expect_error(
    mcp_transport_http(list(url = "https://example.test/mcp", timeout = list(request = 1))),
    "single positive number"
  )
  expect_error(
    mcp_transport_http(list(url = "https://example.test/mcp", timeout = -1)),
    "single positive number"
  )
})

test_that("HTTP request construction leaves proxy and CA settings to curl", {
  withr::local_envvar(
    HTTPS_PROXY = "http://proxy.example.test:8080",
    SSL_CERT_FILE = "/tmp/example-ca.pem",
    CURL_CA_BUNDLE = "/tmp/example-curl-ca.pem"
  )

  transport <- mcp_transport_http(list(url = "https://example.test/mcp"))
  req <- mcp_transport_http_request(
    transport,
    list(jsonrpc = "2.0", id = 1L, method = "tools/list")
  )

  expect_equal(req$url, "https://example.test/mcp")
  expect_equal(req$method, "POST")
  expect_null(req$options$proxy)
  expect_null(req$options$cainfo)
})

test_that("HTTP OAuth resource defaults to the server URL and normalizes", {
  transport <- mcp_transport_http(list(
    url = "https://EXAMPLE.test/mcp",
    oauth = list(client_info = list(client_id = "client-id"))
  ))
  expect_equal(transport$oauth$resource, "https://example.test/mcp")

  transport <- mcp_transport_http(list(
    url = "https://example.test/mcp",
    oauth = list(
      resource = "https://RESOURCE.example.test/custom-resource?tenant=one",
      client_info = list(client_id = "client-id")
    )
  ))
  expect_equal(
    transport$oauth$resource,
    "https://resource.example.test/custom-resource?tenant=one"
  )

  expect_error(
    mcp_transport_http(list(
      url = "https://example.test/mcp#fragment",
      oauth = list(client_info = list(client_id = "client-id"))
    )),
    "must not include a fragment"
  )
})

test_that("client logs redact token-shaped fields", {
  log_file <- withr::local_tempfile()
  withr::local_envvar(MCPTOOLS_CLIENT_LOG = log_file)

  mcp_log_json_message(
    "FROM CLIENT: ",
    list(
      method = "test",
      params = list(
        access_token = "secret-access",
        nested = list(refresh_token = "secret-refresh"),
        visible = "not-secret"
      )
    )
  )

  log_text <- paste(readLines(log_file, warn = FALSE), collapse = "\n")

  expect_match(log_text, "<redacted>", fixed = TRUE)
  expect_match(log_text, "not-secret", fixed = TRUE)
  expect_false(grepl("secret-access|secret-refresh", log_text))
})

# JSON roundtrip ---------------------------------------------------------------
test_that("mcp_tools() supports Streamable HTTP JSON responses", {
  tmp_file <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(
    list(mcpServers = list(remote = list(
      url = "https://example.test/mcp",
      headers = list("X-Test" = "yes")
    ))),
    tmp_file,
    auto_unbox = TRUE
  )
  withr::defer(the$mcp_servers[["remote"]] <- NULL)

  seen <- new.env(parent = emptyenv())
  seen$methods <- character()

  httr2::local_mocked_responses(function(req) {
    message <- req$body$data
    seen$methods <- c(seen$methods, message$method %||% "<response>")

    expect_equal(req$headers$Accept, "application/json, text/event-stream")
    expect_equal(req$headers$`X-Test`, "yes")

    if (identical(message$method, "initialize")) {
      return(httr2::response(
        status_code = 200L,
        url = req$url,
        method = req$method,
        headers = list(
          "Content-Type" = "application/json",
          "MCP-Session-Id" = "session-1"
        ),
        body = charToRaw(to_json(jsonrpc_response(
          message$id,
          result = list(
            protocolVersion = latest_protocol_version,
            capabilities = named_list(),
            serverInfo = list(name = "remote-server", version = "1.0.0")
          )
        )))
      ))
    }

    if (!identical(req$headers$`MCP-Session-Id`, "session-1")) {
      return(httr2::response(status_code = 400L, url = req$url, method = req$method))
    }

    if (identical(message$method, "notifications/initialized")) {
      return(httr2::response(status_code = 202L, url = req$url, method = req$method))
    }

    if (identical(message$method, "tools/list")) {
      return(httr2::response(
        status_code = 200L,
        url = req$url,
        method = req$method,
        headers = list("Content-Type" = "application/json"),
        body = charToRaw(to_json(jsonrpc_response(
          message$id,
          result = list(tools = list(list(
            name = "echo",
            description = "Echo text.",
            inputSchema = list(
              type = "object",
              properties = list(text = list(type = "string", description = "Text to echo.")),
              required = "text"
            )
          )))
        )))
      ))
    }

    if (identical(message$method, "tools/call")) {
      return(httr2::response(
        status_code = 200L,
        url = req$url,
        method = req$method,
        headers = list("Content-Type" = "application/json"),
        body = charToRaw(to_json(jsonrpc_response(
          message$id,
          result = list(
            content = list(list(type = "text", text = paste("echo:", message$params$arguments$text))),
            isError = FALSE
          )
        )))
      ))
    }

    httr2::response(status_code = 500L, url = req$url, method = req$method)
  })

  tools <- mcp_tools(tmp_file)

  expect_length(tools, 1)
  expect_equal(tools[[1]]@name, "echo")
  expect_equal(call_tool(text = "hi", server = "remote", tool = "echo"), "echo: hi")
  expect_equal(
    seen$methods,
    c("initialize", "notifications/initialized", "tools/list", "tools/call")
  )
})

test_that("Streamable HTTP JSON responses must match the request id", {
  transport <- mcp_transport_http(list(url = "https://example.test/mcp"))

  httr2::local_mocked_responses(function(req) {
    httr2::response(
      status_code = 200L,
      url = req$url,
      method = req$method,
      headers = list("Content-Type" = "application/json"),
      body = charToRaw(to_json(jsonrpc_response(999L, result = named_list())))
    )
  })

  expect_error(
    mcp_transport_request(transport, mcp_request_tools_list(id = 2L)),
    "unexpected request id"
  )
})

test_that("HTTP requests transparently reinitialize after a session 404", {
  transport <- mcp_transport_http(list(url = "https://example.test/mcp"))
  transport$session_id <- "old-session"
  transport$protocol_version <- latest_protocol_version

  methods <- character()
  httr2::local_mocked_responses(function(req) {
    message <- req$body$data
    methods <<- c(methods, message$method %||% "<response>")

    # the stale session is rejected; a fresh session starts without one
    if (identical(req$headers$`MCP-Session-Id`, "old-session")) {
      return(httr2::response(status_code = 404L, url = req$url, method = req$method))
    }

    if (identical(message$method, "initialize")) {
      return(httr2::response(
        status_code = 200L,
        url = req$url,
        method = req$method,
        headers = list(
          "Content-Type" = "application/json",
          "MCP-Session-Id" = "new-session"
        ),
        body = charToRaw(to_json(jsonrpc_response(
          message$id,
          result = list(
            protocolVersion = latest_protocol_version,
            capabilities = named_list(),
            serverInfo = list(name = "remote-server", version = "1.0.0")
          )
        )))
      ))
    }

    httr2::response(
      status_code = 200L,
      url = req$url,
      method = req$method,
      headers = list("Content-Type" = "application/json"),
      body = charToRaw(to_json(jsonrpc_response(message$id, result = named_list())))
    )
  })

  response <- mcp_transport_request(transport, mcp_request_tools_list(id = 2L))

  expect_false(is.null(response$result))
  expect_equal(transport$session_id, "new-session")
  expect_equal(
    methods,
    c("tools/list", "initialize", "notifications/initialized", "tools/list")
  )
})

test_that("HTTP requests surface a session-expired error when reinit can't recover", {
  transport <- mcp_transport_http(list(url = "https://example.test/mcp"))
  transport$session_id <- "session-1"
  transport$protocol_version <- latest_protocol_version

  # every session-bearing request 404s; only a sessionless initialize succeeds
  httr2::local_mocked_responses(function(req) {
    message <- req$body$data
    if (!is.null(req$headers$`MCP-Session-Id`)) {
      return(httr2::response(status_code = 404L, url = req$url, method = req$method))
    }

    httr2::response(
      status_code = 200L,
      url = req$url,
      method = req$method,
      headers = list(
        "Content-Type" = "application/json",
        "MCP-Session-Id" = "session-2"
      ),
      body = charToRaw(to_json(jsonrpc_response(
        message$id,
        result = list(
          protocolVersion = latest_protocol_version,
          capabilities = named_list(),
          serverInfo = list(name = "remote-server", version = "1.0.0")
        )
      )))
    )
  })

  expect_error(
    mcp_transport_request(transport, mcp_request_tools_list(id = 2L)),
    class = "mcptools_http_session_expired"
  )
  expect_null(transport$session_id)
})

test_that("Streamable HTTP serializes response-bearing requests", {
  transport <- mcp_transport_http(list(url = "https://example.test/mcp"))

  httr2::local_mocked_responses(function(req) {
    expect_true(transport$http_request_active)
    httr2::response(
      status_code = 200L,
      url = req$url,
      method = req$method,
      headers = list("Content-Type" = "application/json"),
      body = charToRaw(to_json(jsonrpc_response(req$body$data$id, result = named_list())))
    )
  })

  mcp_transport_request(transport, mcp_request_tools_list(id = 2L))
  expect_false(transport$http_request_active)
})

test_that("the active request guard is released after errors", {
  transport <- mcp_transport_http(list(url = "https://example.test/mcp"))

  httr2::local_mocked_responses(function(req) {
    httr2::response(status_code = 500L, url = req$url, method = req$method)
  })

  expect_error(mcp_transport_request(transport, mcp_request_tools_list(id = 2L)))
  expect_false(transport$http_request_active)
})

# mock server roundtrips -------------------------------------------------------
test_that("Streamable HTTP mock server supports JSON responses and cleanup", {
  server <- local_streamable_http_mock_server()
  tmp_file <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(
    list(mcpServers = list(mock_remote = list(url = server$url))),
    tmp_file,
    auto_unbox = TRUE
  )
  withr::defer({
    if ("mock_remote" %in% names(the$mcp_servers)) {
      mcp_transport_close(the$mcp_servers[["mock_remote"]]$transport)
      the$mcp_servers[["mock_remote"]] <- NULL
    }
  })

  tools <- mcp_tools(tmp_file)

  expect_length(tools, 1)
  expect_equal(tools[[1]]@name, "echo")
  expect_equal(
    call_tool(text = "hi", server = "mock_remote", tool = "echo"),
    "echo: hi"
  )
  expect_true(mcp_transport_close(the$mcp_servers[["mock_remote"]]$transport))
  the$mcp_servers[["mock_remote"]] <- NULL

  requests <- server$requests()
  posts <- Filter(function(request) identical(request$method, "POST"), requests)
  methods <- vapply(
    posts,
    function(request) request$body$method %||% "<response>",
    character(1)
  )

  expect_equal(
    methods,
    c("initialize", "notifications/initialized", "tools/list", "tools/call")
  )
  expect_null(posts[[1]]$headers$session_id)
  expect_equal(posts[[3]]$headers$session_id, "session-1")
  expect_true(any(vapply(
    requests,
    function(request) identical(request$method, "DELETE"),
    logical(1)
  )))
})

test_that("Streamable HTTP mock server supports POST SSE", {
  transport <- mcp_transport_http(list(
    url = local_streamable_http_mock_server(post_sse = TRUE)$url
  ))
  withr::defer(mcp_transport_http_close(transport))

  response <- mcp_transport_request(transport, mcp_request_initialize(id = 1L))
  mcp_transport_store_initialize(transport, response)
  mcp_transport_notify(transport, mcp_request_initialized())

  result <- mcp_transport_request(
    transport,
    mcp_request_tool_call(id = 2L, tool = "echo", arguments = list(text = "from sse"))
  )

  expect_equal(result$result$content[[1]]$text, "echo: from sse")
})

test_that("HTTP transport cleanup is a no-op without a session", {
  transport <- mcp_transport_http(list(url = "https://example.test/mcp"))
  expect_false(mcp_transport_http_close(transport))
})

# SSE parsing ------------------------------------------------------------------
test_that("buffered SSE events are parsed into data payloads", {
  events <- mcp_parse_sse_events("id: 1\ndata: {\"a\":1}\n\ndata: {\"b\":2}\n\n")
  expect_length(events, 2)
  expect_equal(events[[1]]$data, "{\"a\":1}")
  expect_equal(events[[2]]$data, "{\"b\":2}")
})

