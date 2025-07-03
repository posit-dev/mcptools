# The MCP server is a proxy. It takes input on stdin, and when the input forms
# valid JSON, it will send the JSON to the session. Then, when it receives the
# response, it will print the response to stdout.
#
# nocov start
# mark as no test coverage as, when this is tested in `test-server.R`, the
# function is called in a separate R process and thus isn't picked up by
# coverage tools

#' @param tools A list of tools created with [ellmer::tool()] that will be
#' available from the server or a file path to an .R file that, when sourced,
#' will return a list of tools. Any list that could be passed to
#' `Chat$set_tools()` can be passed here. By default, the package won't serve
#' any tools other than those needed to communicate with active R sessions.
#'
#' @rdname server
#' @export
#'
#' @examples
#' # should only be run non-interactively, and will block the current R process
#' # once called.
#' if (FALSE) {
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
mcp_server <- function(tools = NULL) {
  # TODO: should this actually be a check for being called within Rscript or not?
  check_not_interactive()
  set_server_tools(tools)

  cv <- nanonext::cv()
  reader_socket <- nanonext::read_stdin()
  on.exit(nanonext::reap(reader_socket))
  nanonext::pipe_notify(reader_socket, cv, remove = TRUE, flag = TRUE)

  the$server_socket <- nanonext::socket("poly")
  on.exit(nanonext::reap(the$server_socket), add = TRUE)
  nanonext::dial(the$server_socket, url = sprintf("%s%d", the$socket_url, 1L))

  client <- nanonext::recv_aio(reader_socket, mode = "string", cv = cv)
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
      # two tools provided by mcptools itself which must be executed in
      # the server rather than a session (#18)
      tool_name %in%
        c("list_r_sessions", "select_r_session") ||
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
  log_file <- mcptools_log_file()
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

  data$tool <- get_mcptools_tools()[[tool_name]]@fun
  data
}

# nocov end
