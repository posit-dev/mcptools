# The MCP server is a proxy. It takes input on stdin, and when the input forms
# valid JSON, it will send the JSON to the host. Then, when it receives the
# response, it will print the response to stdout.
#' @rdname mcp
#' @export
mcp_server <- function() {
  # TODO: should this actually be a check for being called within Rscript or not?
  check_not_interactive()

  the$reader_socket <- nanonext::read_stdin()
  the$server_socket <- nanonext::socket("poly")
  nanonext::dial(the$server_socket, url = sprintf("%s%d", acquaint_socket, 1L))

  schedule_handle_message_from_client()
  schedule_handle_message_from_host()

  # Pump the event loop
  while (TRUE) {
    later::run_now(Inf)
  }
}

handle_message_from_client <- function(line) {
  schedule_handle_message_from_client()
  # TODO: Read multiple lines all at once (because the client can send
  # multiple requests quickly), and then handle each line separately.
  # Otherwise, the message throughput will be bound by the polling rate.

  if (length(line) == 0) {
    return()
  }

  logcat("FROM CLIENT: ", line)

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
        tools = get_all_btw_tools()
      )
    )

    cat_json(res)
  } else if (data$method == "tools/call") {
    result <- forward_request(line)

    # } else if (data$method == "prompts/list") {
    # } else if (data$method == "resources/list") {
  } else if (is.null(data$id)) {
    # If there is no `id` in the request, then this is a notification and the
    # client does not expect a response.
    if (data$method == "notifications/initialized") {
    }
  } else {
    cat_json(jsonrpc_response(
      data$id,
      error = list(code = -32601, message = "Method not found")
    ))
  }

}

schedule_handle_message_from_client <- function() {
  r <- nanonext::recv_aio(the$reader_socket, mode = "string")
  promises::as.promise(r)$then(handle_message_from_client)
}

handle_message_from_host <- function(data) {
  if (!is.character(data)) {
    return()
  }

  schedule_handle_message_from_host()

  logcat("FROM HOST: ", data)

  # The response_text is already JSON, so we don't need to use cat_json()
  nanonext::write_stdout(data)
}

schedule_handle_message_from_host <- function() {
  r <- nanonext::recv_aio(the$server_socket, mode = "string")
  promises::as.promise(r)$then(handle_message_from_host)
}

forward_request <- function(data) {
  logcat("TO HOST: ", data)

  nanonext::send_aio(the$server_socket, data, mode = "raw")
}

# This process will be launched by the MCP client, so stdout/stderr aren't
# visible. This function will log output to the `logfile` so that you can view
# it.
logcat <- function(x, ..., append = TRUE) {
  log_file <- acquaint_log_file()
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
      name = "R acquaint server",
      version = "0.0.1"
    ),
    instructions = "This provides information about a running R session."
  )
}

# Hacky way of getting tools from btw
get_all_btw_tools <- function() {
  dummy_provider <- ellmer::Provider("dummy", "dummy", "dummy")

  .btw_tools <- getNamespace("btw")[[".btw_tools"]]
  tools <- lapply(unname(.btw_tools), function(tool_obj) {
    tool <- tool_obj$tool()

    if (is.null(tool)) {
      return(NULL)
    }

    as_json <- getNamespace("ellmer")[["as_json"]]
    inputSchema <- compact(as_json(dummy_provider, tool@arguments))
    # This field is present but shouldn't be
    inputSchema$description <- NULL

    list(
      name = tool@name,
      description = tool@description,
      inputSchema = inputSchema
    )
  })

  compact(tools)
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

mcp_discover <- function() {
  sock <- nanonext::socket("poly")
  on.exit(nanonext::reap(sock))
  cv <- nanonext::cv()
  monitor <- nanonext::monitor(sock, cv)
  suppressWarnings(
    for (i in seq_len(1024L)) {
      nanonext::dial(
        sock,
        url = sprintf("%s%d", acquaint_socket, i),
        autostart = NA
      ) &&
        break
    }
  )
  pipes <- nanonext::read_monitor(monitor)
  res <- lapply(seq_along(pipes), function(x) nanonext::recv_aio(sock))
  lapply(
    pipes,
    function(x) nanonext::send_aio(sock, "", mode = "raw", pipe = x)
  )
  nanonext::collect_aio_(res)
}

select_host <- function(i) {
  lapply(the$server_socket[["dialer"]], nanonext::reap)
  attr(the$server_socket, "dialer") <- NULL
  nanonext::dial(
    the$server_socket,
    url = sprintf("%s%d", acquaint_socket, as.integer(i))
  )
}
