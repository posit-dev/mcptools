# The MCP server is a proxy. It takes input on stdin, and when the input forms
# valid JSON, it will send the JSON to the session. Then, when it receives the
# response, it will print the response to stdout.
#
# nocov start
# mark as no test coverage as, when this is tested in `test-server.R`, the
# function is called in a separate R process and thus isn't picked up by
# coverage tools

#' R as a server: Configure R-based tools with LLM-enabled apps
#'
#' @description
#' `mcp_server()` implements a model context protocol server with arbitrary
#' R functions as its tools. Optionally, calling `mcp_session()` in an
#' interactive R session allows those tools to execute inside of that session.
#'
#' @section Configuration:
#'
#' ## Local server (default, via stdio)
#'
#' [mcp_server()] can be configured with MCP clients via the `Rscript`
#' command. For example, to use with Claude Desktop, paste the following in your
#' Claude Desktop configuration (on macOS, at
#' `file.edit("~/Library/Application Support/Claude/claude_desktop_config.json")`):
#'
#' ```json
#' {
#'   "mcpServers": {
#'     "r-mcptools": {
#'       "command": "Rscript",
#'       "args": ["-e", "mcptools::mcp_server()"]
#'     }
#'   }
#' }
#' ```
#'
#' Or, to use with Claude Code, you might type in a terminal:
#'
#' ```bash
#' claude mcp add -s "user" r-mcptools Rscript -e "mcptools::mcp_server()"
#' ```
#'
#' ## Remote server (via http)
#'
#' To run an HTTP server instead, use `type = "http"`:
#'
#' ```r
#' # Start HTTP server on default port (8080)
#' mcp_server(type = "http")
#'
#' # Or specify custom host and port
#' mcp_server(type = "http", host = "127.0.0.1", port = 9000)
#' ```
#'
#' The server will listen for HTTP POST requests containing JSON-RPC messages.
#'
#' ## Posit Connect
#'
#' To deploy an HTTP MCP server to Posit Connect, add a `_server.yml` file to
#' the project directory:
#'
#' ```yaml
#' engine: mcptools
#' tools: tools.R
#' ```
#'
#' The `tools` file should return a list of [ellmer::tool()] objects. Deploy
#' the project as an R API and mark it as MCP content:
#'
#' ```r
#' rsconnect::deployAPI(".", contentCategory = "mcp")
#' ```
#'
#' Use the Connect content URL with `/mcp` appended as the MCP endpoint. For
#' example, if the content URL is `https://connect.example.com/content/abc123/`,
#' use `https://connect.example.com/content/abc123/mcp`. mcptools accepts
#' requests at any path, so the content URL itself also works.
#' If you cannot set `contentCategory = "mcp"` during deployment, set the MCP
#' category in Connect after deploying and set minimum processes to at least 1.
#'
#' Connect deployments run tools inside the deployed R process by default.
#' Session discovery with [mcp_session()] is intended for local desktop R
#' sessions and is disabled by default on Connect.
#'
#' **mcp_server() is not intended for interactive use.**
#'
#' The server interfaces with the MCP client. If you'd like tools to have access
#' to variables inside of an interactive R session, call
#' `mcp_session()` to make your R session available to the server.
#' Place a call to `mcptools::mcp_session()` in your `.Rprofile`, perhaps with
#' `usethis::edit_r_profile()`, to make every interactive R session you start
#' available to the server.
#'
#' On Windows, you may need to configure the full path to the Rscript executable.
#' Examples for Claude Code on WSL and Claude Desktop on Windows are shown
#' at <https://github.com/posit-dev/mcptools/issues/41#issuecomment-3036617046>.
#'
#' @param tools Optional collection of tools to expose. Supply either a list
#'   of objects created by [ellmer::tool()] or a path to an `.R` file that,
#'   when sourced, yields such a list. Defaults to `NULL`, which serves only
#'   the built-in session tools when `session_tools` is `TRUE`. Note that
#'   **tools are associated with the `mcp_server()`** rather than with
#'   `mcp_session()`s; to determine what tools are available in a session,
#'   set the `tools` argument to `mcp_server()`.
#' @param ... Reserved for future use; currently ignored.
#' @param type Transport type: `"stdio"` for standard input/output (default),
#'   or `"http"` for HTTP-based transport.
#' @param host Host to bind to when using HTTP transport. Defaults to
#'   `"127.0.0.1"` (localhost) for security. Ignored for stdio transport.
#' @param port Port to bind to when using HTTP transport. Defaults to the value
#'   of the `MCPTOOLS_PORT` environment variable, or 8080 if not set. Ignored
#'   for stdio transport.
#' @param session_tools Logical value whether to include the built-in session
#'   tools (`list_r_sessions`, `select_r_session`) that work with
#'   `mcp_session()`. Defaults to `TRUE`. Note that the tools to interface with
#'   sessions are still first routed through the `mcp_server()`.
#'
#' @returns
#' `mcp_server()` and `mcp_session()` are both called primarily for their
#'  side-effects.
#'
#' * `mcp_server()` blocks the R process it's called in indefinitely and isn't
#'   intended for interactive use.
#' * `mcp_session()` makes the interactive R session it's called in available to
#'   MCP servers. It returns invisibly the \pkg{nanonext} socket used for
#'   communicating with the server. Call [close()] on the socket to stop the
#'   session.
#'
#' @seealso
#' - The "R as an MCP server" vignette at
#' `vignette("server", package = "mcptools")` delves into further detail
#' on setup and customization.
#' - These functions implement R as an MCP _server_. To use R as an MCP _client_,
#' i.e. to configure tools from third-party MCP servers with ellmer chats, see
#' [mcp_tools()].
#'
#' @examples
#' # should only be run non-interactively, and will block the current R process
#' # once called.
#' if (identical(Sys.getenv("MCPTOOLS_CAN_BLOCK_PROCESS"), "true")) {
#' # to start a server with a tool to draw numbers from a random normal:
#' library(ellmer)
#'
#' tool_rnorm <- tool(
#'   rnorm,
#'   "Draw numbers from a random normal distribution",
#'   n = type_integer("The number of observations. Must be a positive integer."),
#'   mean = type_number("The mean value of the distribution."),
#'   sd = type_number("The standard deviation of the distribution. Must be a non-negative number.")
#' )
#'
#' mcp_server(tools = list(tool_rnorm))
#'
#' # can also supply a file path as `tools`
#' readLines(system.file("example-ellmer-tools.R", package = "mcptools"))
#'
#' mcp_server(tools = system.file("example-ellmer-tools.R", package = "mcptools"))
#' }
#'
#' if (interactive()) {
#'   mcp_session()
#' }
#'
#' @name server
#' @export
mcp_server <- function(
  tools = NULL,
  ...,
  type = c("stdio", "http"),
  host = "127.0.0.1",
  port = as.integer(Sys.getenv("MCPTOOLS_PORT", "8080")),
  session_tools = TRUE
) {
  check_not_interactive()
  type <- rlang::arg_match(type)

  nanonext::reap(the$session_socket) # in case session was started in .Rprofile
  the$sessions_enabled <- isTRUE(session_tools)
  set_server_tools(tools, session_tools = the$sessions_enabled)

  switch(
    type,
    stdio = mcp_server_stdio(),
    http = mcp_server_http(host = host, port = port)
  )
}

mcp_server_stdio <- function() {
  cv <- nanonext::cv()

  reader_socket <- nanonext::read_stdin()
  on.exit(nanonext::reap(reader_socket))
  nanonext::pipe_notify(reader_socket, cv, remove = TRUE, flag = TRUE)
  client <- nanonext::recv_aio(reader_socket, mode = "string", cv = cv)

  if (the$sessions_enabled) {
    the$server_socket <- nanonext::socket("poly")
    on.exit(nanonext::reap(the$server_socket), add = TRUE)
    nanonext::dial(the$server_socket, url = sprintf("%s%d", the$socket_url, 1L))
  }

  while (nanonext::wait(cv)) {
    if (!nanonext::unresolved(client)) {
      handle_message_from_client(client$data)
      client <- nanonext::recv_aio(reader_socket, mode = "string", cv = cv)
    }
  }
}

mcp_server_http <- function(host = "127.0.0.1", port = 8080) {
  if (the$sessions_enabled) {
    the$server_socket <- nanonext::socket("poly")
    on.exit(nanonext::reap(the$server_socket), add = TRUE)
    nanonext::dial(the$server_socket, url = sprintf("%s%d", the$socket_url, 1L))
  }

  app <- list(
    call = function(req) {
      handle_http_request(req)
    }
  )

  server <- httpuv::startServer(host = host, port = port, app = app)
  on.exit(httpuv::stopServer(server), add = TRUE)

  cat(sprintf("MCP server listening on http://%s:%d\n", host, port))

  httpuv::service(Inf)
}

handle_http_request <- function(req) {
  if (!validate_shared_secret(req)) {
    return(http_forbidden("Invalid shared secret"))
  }

  if (!validate_host(req)) {
    return(http_forbidden("Invalid Host"))
  }

  if (!validate_origin(req)) {
    return(http_forbidden("Invalid Origin"))
  }

  if (!validate_http_protocol_version(req)) {
    return(http_bad_request("Invalid or unsupported MCP-Protocol-Version"))
  }

  if (req$REQUEST_METHOD == "POST") {
    return(handle_http_post(req))
  } else if (req$REQUEST_METHOD == "GET") {
    return(handle_http_get(req))
  } else {
    return(list(
      status = 405L,
      headers = list("Allow" = "POST"),
      body = "Method Not Allowed"
    ))
  }
}

http_forbidden <- function(error) {
  list(
    status = 403L,
    headers = list("Content-Type" = "application/json"),
    body = to_json(list(error = error))
  )
}

http_bad_request <- function(error) {
  list(
    status = 400L,
    headers = list("Content-Type" = "application/json"),
    body = to_json(list(error = error))
  )
}

validate_shared_secret <- function(req) {
  shared_secret <- http_shared_secret()
  if (!nzchar(shared_secret)) {
    return(TRUE)
  }

  header <- req$HTTP_PLUMBER_SHARED_SECRET
  if (is.null(header)) {
    return(FALSE)
  }

  constant_time_equal(header, shared_secret)
}

http_shared_secret <- function() {
  first_nonempty_string(
    the$http_shared_secret,
    getOption("mcptools.http_shared_secret", NULL),
    getOption("plumber2.sharedSecret", "")
  )
}

validate_host <- function(req) {
  trusted_hosts <- http_trusted_hosts()
  if (!length(trusted_hosts)) {
    return(TRUE)
  }

  host <- req$HTTP_HOST
  if (is.null(host)) {
    return(FALSE)
  }

  host %in% trusted_hosts
}

http_trusted_hosts <- function() {
  unique(c(
    the$http_trusted_hosts,
    getOption("mcptools.http_trusted_hosts", character()),
    split_envvar(Sys.getenv("MCPTOOLS_HTTP_TRUSTED_HOSTS", ""))
  ))
}

validate_origin <- function(req) {
  origin <- req$HTTP_ORIGIN
  if (is.null(origin)) {
    return(TRUE)
  }

  parsed <- url_parse_or_null(origin)
  if (is.null(parsed)) {
    return(FALSE)
  }

  allowed_hosts <- c("localhost", "127.0.0.1", "[::1]")

  origin %in% http_allowed_origins() || parsed$hostname %in% allowed_hosts
}

http_allowed_origins <- function() {
  unique(c(
    the$http_allowed_origins,
    getOption("mcptools.http_allowed_origins", character()),
    split_envvar(Sys.getenv("MCPTOOLS_HTTP_ALLOWED_ORIGINS", ""))
  ))
}

validate_http_protocol_version <- function(req) {
  version <- req$HTTP_MCP_PROTOCOL_VERSION
  is.null(version) || is_supported_protocol_version(version)
}

handle_http_post <- function(req) {
  body_raw <- req$rook.input$read()
  body_text <- rawToChar(body_raw)

  data <- tryCatch(
    jsonlite::parse_json(body_text),
    error = function(e) NULL
  )

  if (is.null(data)) {
    return(http_bad_request("Invalid JSON"))
  }

  if (is.null(data$id)) {
    result <- handle_http_notification_or_response(data)
    return(list(
      status = 202L,
      headers = list("Content-Type" = "application/json"),
      body = ""
    ))
  }

  result <- handle_http_request_message(
    data,
    protocol_version = http_message_protocol_version(data, req)
  )

  list(
    status = 200L,
    headers = list("Content-Type" = "application/json"),
    body = to_json(result)
  )
}

handle_http_get <- function(req) {
  list(
    status = 405L,
    headers = list(
      "Allow" = "POST",
      "Content-Type" = "text/plain"
    ),
    body = paste(
      "mcptools MCP endpoint is running.",
      "",
      "HTTP GET/SSE is not supported; use POST from an MCP Streamable HTTP client.",
      sep = "\n"
    )
  )
}

handle_http_notification_or_response <- function(data) {
  NULL
}

http_message_protocol_version <- function(data, req) {
  if (identical(data$method, "initialize")) {
    client_version <- data$params$protocolVersion %||% latest_protocol_version
    return(negotiate_protocol_version(client_version))
  }

  req$HTTP_MCP_PROTOCOL_VERSION %||% default_http_protocol_version
}

handle_http_request_message <- function(
  data,
  protocol_version = the$protocol_version %||% latest_protocol_version
) {
  if (data$method == "initialize") {
    # while protocolVersion is required per spec,
    # we fall back rather than erroring
    client_version <- data$params$protocolVersion %||% latest_protocol_version
    negotiated <- negotiate_protocol_version(client_version)
    the$protocol_version <- negotiated
    return(jsonrpc_response(data$id, capabilities(negotiated)))
  } else if (data$method == "tools/list") {
    return(jsonrpc_response(
      data$id,
      list(tools = get_mcptools_tools_as_json(protocol_version))
    ))
  } else if (data$method == "tools/call") {
    data$protocolVersion <- protocol_version
    tool_name <- data$params$name
    if (
      !the$sessions_enabled ||
        tool_name %in% c("list_r_sessions", "select_r_session") ||
        !nanonext::stat(the$server_socket, "pipes")
    ) {
      prepared <- append_tool_fn(data)
      if (inherits(prepared, "jsonrpc_error")) {
        return(prepared)
      }
      return(execute_tool_call(prepared))
    } else {
      prepared <- append_tool_fn(data)
      if (inherits(prepared, "jsonrpc_error")) {
        return(prepared)
      }

      return(forward_request(data))
    }
  } else {
    return(jsonrpc_response(
      data$id,
      error = list(code = -32601, message = "Method not found")
    ))
  }
}

handle_message_from_client <- function(line) {
  if (length(line) == 0) {
    return()
  }

  logcat(c("FROM CLIENT: ", line))

  data <- NULL

  tryCatch(
    {
      data <- jsonlite::parse_json(line)
    },
    error = function(e) {
      # Invalid JSON. Possibly unfinished multi-line JSON message?
    }
  )

  if (is.null(data)) {
    # Can get here if there's an empty line
    return()
  }

  if (!is.list(data) || is.null(data$method)) {
    cat_json(jsonrpc_response(
      data$id,
      error = list(code = -32600, message = "Invalid Request")
    ))
    return()
  }

  # If we made it here, it's valid JSON

  if (data$method == "initialize") {
    # while protocolVersion is required per spec,
    # we fall back rather than erroring
    client_version <- data$params$protocolVersion %||% latest_protocol_version
    negotiated <- negotiate_protocol_version(client_version)
    the$protocol_version <- negotiated
    res <- jsonrpc_response(data$id, capabilities(negotiated))
    cat_json(res)
  } else if (data$method == "tools/list") {
    res <- jsonrpc_response(
      data$id,
      list(
        tools = get_mcptools_tools_as_json()
      )
    )

    cat_json(res)
  } else if (data$method == "tools/call") {
    tool_name <- data$params$name
    if (
      !the$sessions_enabled ||
        # two tools provided by mcptools itself which must be executed in
        # the server rather than a session (#18)
        tool_name %in% c("list_r_sessions", "select_r_session") ||
        # when session handling is disabled, never forward to sessions
        # with no sessions available, just execute tools in the server (#36)
        !nanonext::stat(the$server_socket, "pipes")
    ) {
      handle_request(data)
    } else {
      result <- forward_request(data)
      logcat(c("FROM SESSION: ", to_json(result)))
      cat_json(result)
    }
  } else if (is.null(data$id)) {
    # If there is no `id` in the request, then this is a notification and the
    # client does not expect a response.
    if (data$method == "notifications/initialized") {}
  } else {
    cat_json(jsonrpc_response(
      data$id,
      error = list(code = -32601, message = "Method not found")
    ))
  }
}

handle_message_from_session <- function(data) {
  if (!is.character(data)) {
    return()
  }

  logcat(c("FROM SESSION: ", data))

  # The response_text is already JSON, so we don't need to use cat_json()
  nanonext::write_stdout(data)
}

forward_request <- function(data) {
  logcat(c("TO SESSION: ", jsonlite::toJSON(data)))

  prepared <- append_tool_fn(data)

  if (inherits(prepared, "jsonrpc_error")) {
    return(prepared)
  }

  drain_stale_forwarded_responses()

  timeout <- session_response_timeout()
  send_result <- nanonext::send(
    the$server_socket,
    prepared,
    mode = "serial",
    block = timeout
  )

  if (nanonext::is_error_value(send_result) || !identical(send_result, 0L)) {
    return(session_forwarding_error(
      data$id,
      "Failed to send the request to the selected R session."
    ))
  }

  receive_forwarded_response(data$id, timeout)
}

receive_forwarded_response <- function(id, timeout) {
  deadline <- Sys.time() + timeout / 1000

  repeat {
    response_raw <- nanonext::recv(
      the$server_socket,
      mode = "character",
      block = remaining_timeout(deadline)
    )

    if (!is.character(response_raw) || nanonext::is_error_value(response_raw)) {
      return(session_forwarding_error(
        id,
        sprintf(
          "Timed out waiting for a response from the selected R session after %s.",
          format_timeout(timeout)
        )
      ))
    }

    response <- tryCatch(
      jsonlite::parse_json(response_raw),
      error = function(err) {
        session_forwarding_error(
          id,
          paste(
            "Received an invalid response from the selected R session:",
            conditionMessage(err)
          )
        )
      }
    )

    if (!is.list(response)) {
      return(session_forwarding_error(
        id,
        "Received an invalid response from the selected R session."
      ))
    }

    if (matches_jsonrpc_id(response, id)) {
      return(response)
    }

    logcat(c(
      "Ignoring stale forwarded response for request id ",
      format_jsonrpc_id(response)
    ))
  }
}

drain_stale_forwarded_responses <- function() {
  repeat {
    response_raw <- nanonext::recv(
      the$server_socket,
      mode = "character",
      block = FALSE
    )

    if (!is.character(response_raw) || nanonext::is_error_value(response_raw)) {
      return(invisible())
    }

    logcat(c("Ignoring queued stale forwarded response: ", response_raw))
  }
}

session_forwarding_error <- function(id, message) {
  jsonrpc_response(
    id,
    error = list(code = -32603, message = message)
  )
}

remaining_timeout <- function(deadline) {
  remaining <- as.numeric(difftime(deadline, Sys.time(), units = "secs"))
  max(1L, as.integer(ceiling(remaining * 1000)))
}

matches_jsonrpc_id <- function(response, id) {
  identical(response$id, id)
}

session_response_timeout <- function() {
  seconds <- getOption(
    "mcptools.session_response_timeout_seconds",
    Sys.getenv("MCPTOOLS_SESSION_RESPONSE_TIMEOUT_SECONDS", "120")
  )
  seconds <- suppressWarnings(as.numeric(seconds))

  if (length(seconds)) {
    seconds <- seconds[[1]]
  }

  if (!length(seconds) || is.na(seconds) || seconds <= 0) {
    seconds <- 120
  }

  as.integer(ceiling(seconds * 1000))
}

format_timeout <- function(timeout) {
  seconds <- timeout / 1000
  if (identical(seconds, 1)) {
    return("1 second")
  }

  sprintf("%s seconds", seconds)
}

format_jsonrpc_id <- function(response) {
  if (is.null(response$id)) {
    return("<missing>")
  }

  paste(response$id, collapse = ", ")
}

# This process will be launched by the MCP client, so stdout/stderr aren't
# visible. This function will log output to the `logfile` so that you can view
# it.
logcat <- function(x, ..., append = TRUE) {
  log_file <- mcptools_server_log()
  cat(x, "\n", sep = "", append = append, file = log_file)
}

cat_json <- function(x) {
  nanonext::write_stdout(to_json(x))
}

capabilities <- function(protocol_version = latest_protocol_version) {
  res <- list(
    protocolVersion = protocol_version,
    capabilities = list(
      # logging = named_list(),
      prompts = named_list(
        listChanged = FALSE
      ),
      resources = named_list(
        subscribe = FALSE,
        listChanged = FALSE
      ),
      tools = named_list(
        listChanged = FALSE
      )
    ),
    serverInfo = list(
      name = "R mcptools server",
      version = "0.0.1"
    )
  )

  # `instructions` was introduced in protocol version 2025-03-26
  if (protocol_version_gte(protocol_version, "2025-03-26")) {
    res$instructions <- "This provides information about a running R session."
  }

  res
}

tool_as_json <- function(tool, protocol_version = latest_protocol_version) {
  dummy_provider <- ellmer::Provider("dummy", "dummy", "dummy")

  as_json <- getNamespace("ellmer")[["as_json"]]
  inputSchema <- compact(as_json(dummy_provider, tool@arguments))
  # This field is present but shouldn't be
  inputSchema$description <- NULL
  # compact() drops zero-length elements, so properties gets stripped for

  # no-argument tools. Rather than reworking compact(), patch it here.
  if (is.null(inputSchema$properties)) {
    inputSchema$properties <- structure(list(), names = character())
  }

  compact(list(
    name = tool@name,
    title = tool_title_as_json(tool@annotations, protocol_version),
    description = tool@description,
    inputSchema = inputSchema,
    annotations = tool_annotations_as_json(tool@annotations)
  ))
}

tool_title_as_json <- function(annotations, protocol_version) {
  if (protocol_version_lt(protocol_version, "2025-06-18")) {
    return(NULL)
  }

  annotations$title
}

tool_annotations_as_json <- function(annotations) {
  if (!length(annotations)) {
    return(NULL)
  }

  mcp_names <- c(
    read_only_hint = "readOnlyHint",
    destructive_hint = "destructiveHint",
    idempotent_hint = "idempotentHint",
    open_world_hint = "openWorldHint"
  )
  annotation_names <- names(annotations)
  matched_names <- annotation_names %in% names(mcp_names)
  annotation_names[matched_names] <- mcp_names[annotation_names[matched_names]]
  names(annotations) <- annotation_names

  annotations
}

compact <- function(.x) {
  Filter(length, .x)
}

check_not_interactive <- function(call = caller_env()) {
  if (interactive()) {
    cli::cli_abort(
      c(
        "This function is not intended for interactive use.",
        "i" = "See {.help {.fn mcp_server}} for instructions on configuring this
       function with applications"
      ),
      call = call
    )
  }
}

handle_request <- function(data) {
  prepared <- append_tool_fn(data)

  if (inherits(prepared, "jsonrpc_error")) {
    result <- prepared
  } else {
    result <- execute_tool_call(prepared)
  }

  logcat(c("FROM SERVER: ", to_json(result)))
  cat_json(result)
}

# the session needs access to the function called by the server; in addition
# to the raw jsonrpc request, append the relevant R function if the request
# is a `tools/call`
append_tool_fn <- function(data) {
  if (!identical(data$method, "tools/call")) {
    return(data)
  }

  tool_name <- data$params$name

  if (!tool_name %in% names(get_mcptools_tools())) {
    return(structure(
      jsonrpc_response(
        data$id,
        error = list(code = -32601, message = "Method not found")
      ),
      class = c("jsonrpc_error", "list")
    ))
  }

  data$protocolVersion <- data$protocolVersion %||%
    the$protocol_version %||%
    latest_protocol_version
  data$tool <- get_mcptools_tools()[[tool_name]]
  data
}

# nocov end
