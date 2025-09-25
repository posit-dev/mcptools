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
#' [mcp_server()] should be configured with the MCP clients via the `Rscript`
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
#'   the built-in session tools when `session_tools` is `TRUE`.
#' @param ... Reserved for future use; currently ignored.
#' @param session_tools Logical value whether to include the built-in session
#'   tools (`list_r_sessions`, `select_r_session`) that work with
#'   `mcp_session()`. Defaults to `TRUE`.
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
mcp_server <- function(tools = NULL, ..., session_tools = TRUE) {

  check_not_interactive()
  nanonext::reap(the$session_socket) # in case session was started in .Rprofile
  the$sessions_enabled <- isTRUE(session_tools)
  set_server_tools(tools, session_tools = the$sessions_enabled)

  cv <- nanonext::cv()

  reader_socket <- nanonext::read_stdin()
  on.exit(nanonext::reap(reader_socket))
  nanonext::pipe_notify(reader_socket, cv, remove = TRUE, flag = TRUE)
  client <- nanonext::recv_aio(reader_socket, mode = "string", cv = cv)

  if (!the$sessions_enabled) {
    while (nanonext::wait(cv)) {
      if (!nanonext::unresolved(client)) {
        handle_message_from_client(client$data)
        client <- nanonext::recv_aio(reader_socket, mode = "string", cv = cv)
      }
    }
    return()
  }

  the$server_socket <- nanonext::socket("poly")
  on.exit(nanonext::reap(the$server_socket), add = TRUE)
  nanonext::dial(the$server_socket, url = sprintf("%s%d", the$socket_url, 1L))
  session <- nanonext::recv_aio(the$server_socket, mode = "string", cv = cv)

  while (nanonext::wait(cv)) {
    if (!nanonext::unresolved(session)) {
      handle_message_from_session(session$data)
      session <- nanonext::recv_aio(the$server_socket, mode = "string", cv = cv)
    }
    if (!nanonext::unresolved(client)) {
      handle_message_from_client(client$data)
      client <- nanonext::recv_aio(reader_socket, mode = "string", cv = cv)
    }
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
  }

  # If we made it here, it's valid JSON

  if (data$method == "initialize") {
    res <- jsonrpc_response(data$id, capabilities())
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

  nanonext::send_aio(the$server_socket, prepared, mode = "serial")
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

capabilities <- function() {
  list(
    protocolVersion = "2024-11-05",
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
    ),
    instructions = "This provides information about a running R session."
  )
}

tool_as_json <- function(tool) {
  dummy_provider <- ellmer::Provider("dummy", "dummy", "dummy")

  as_json <- getNamespace("ellmer")[["as_json"]]
  inputSchema <- compact(as_json(dummy_provider, tool@arguments))
  # This field is present but shouldn't be
  inputSchema$description <- NULL

  list(
    name = tool@name,
    description = tool@description,
    inputSchema = inputSchema
  )
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
      class = "jsonrpc_error"
    ))
  }

  data$tool <- get_mcptools_tools()[[tool_name]]
  data
}

# nocov end
