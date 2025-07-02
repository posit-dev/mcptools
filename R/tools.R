set_server_tools <- function(x, x_arg = caller_arg(x), call = caller_env()) {
  if (is.null(x)) {
    the$server_tools <- c(list(list_r_sessions_tool, select_r_session_tool))
    return()
  }

  # evaluate eagerly so that caller arg is correct if `looks_like_r_file()`
  # but output type isn't correct
  force(x_arg)
  if (looks_like_r_file(x)) {
    x <- tryCatch(
      {
        source_tools(x)
      },
      error = function(err) {
        cli::cli_abort(
          "Sourcing the {.arg {x_arg}} file {.file x} failed.",
          parent = err,
          call = call
        )
      }
    )
  }

  if (!is_list(x) || !all(vapply(x, inherits, logical(1), "ellmer::ToolDef"))) {
    msg <-
      "{.arg {x_arg}} must be a list of tools created with {.fn ellmer::tool}
       or a .R file path that returns a list of ellmer tools when sourced."
    if (inherits(x, "ellmer::ToolDef")) {
      msg <- c(msg, "i" = "Did you mean to wrap {.arg {x_arg}} in `list()`?")
    }
    cli::cli_abort(msg, call = call)
  }

  if (
    any(
      vapply(x, \(.x) .x@name, character(1)) %in%
        c("list_r_sessions", "select_r_session")
    )
  ) {
    cli::cli_abort(
      "The tool names {.field list_r_sessions} and {.field select_r_session} are 
       reserved by {.pkg acquaint}.",
      call = call
    )
  }

  the$server_tools <- c(
    x,
    list(
      list_r_sessions_tool,
      select_r_session_tool
    )
  )
}

looks_like_r_file <- function(x) {
  is_string(x) &&
    file.exists(x) &&
    grepl("\\.r$", x, ignore.case = TRUE)
}

source_tools <- function(x) {
  source(x, local = TRUE)$value
}

# These two functions are supplied to the client as tools and allow the client
# to discover R sessions which have called `acquaint::mcp_session()`. They
# are "model-facing" rather than user-facing.
list_r_sessions <- function() {
  sock <- nanonext::socket("poly")
  on.exit(nanonext::reap(sock))
  cv <- nanonext::cv()
  monitor <- nanonext::monitor(sock, cv)
  for (i in seq_len(1024L)) {
    if (
      nanonext::dial(
        sock,
        url = sprintf("%s%d", the$socket_url, i),
        autostart = NA,
        fail = "none"
      ) &&
        i > 8L
    ) {
      break
    }
  }
  pipes <- nanonext::read_monitor(monitor)
  res <- lapply(
    pipes,
    function(x) nanonext::recv_aio(sock, mode = "string", timeout = 5000L)
  )
  lapply(
    pipes,
    function(x) nanonext::send_aio(sock, character(), mode = "serial", pipe = x)
  )
  sort(as.character(nanonext::collect_aio_(res)))
}

list_r_sessions_tool <-
  ellmer::tool(
    .fun = list_r_sessions,
    .description = paste(
      "List the R sessions that are available to access.",
      "R sessions which have run `acquaint::mcp_session()` will appear here.",
      "In the output, start each session with 'Session #' and do NOT otherwise",
      "prefix any index numbers to the output.",
      "In general, do not use this tool unless asked to list or",
      "select a specific R session.",
      "Given the output of this tool, report the users to the user.",
      "Do NOT make a choice of R session based on the results of the tool",
      "and call select_r_session unless the user asks you to specifically."
    )
  )

select_r_session <- function(session) {
  nanonext::reap(the$server_socket[["dialer"]][[1L]])
  attr(the$server_socket, "dialer") <- NULL
  nanonext::dial(
    the$server_socket,
    url = sprintf("%s%d", the$socket_url, session)
  )
  sprintf("Selected session %d successfully.", session)
}

select_r_session_tool <-
  ellmer::tool(
    .fun = select_r_session,
    .description = paste(
      "Choose the R session of interest.",
      "Use the `list_r_sessions` tool to discover potential sessions.",
      "In general, do not use this tool unless asked to select a specific R",
      "session; the tools available to you have a default R session",
      "that is usually the one the user wants.",
      "Do not call this tool immediately after calling list_r_sessions",
      "unless you've been asked to select an R session and haven't yet",
      "called list_r_sessions.",
      "Your choice of session will persist after the tool is called; only",
      "call this tool more than once if you need to switch between sessions."
    ),
    session = ellmer::type_integer("The R session number to select.")
  )

get_acquaint_tools <- function() {
  # must be called inside of the server session
  res <- the$server_tools
  set_names(res, vapply(res, \(x) x@name, character(1)))
}

get_acquaint_tools_as_json <- function() {
  tools <- lapply(unname(get_acquaint_tools()), tool_as_json)

  compact(tools)
}

execute_tool_call <- function(data) {
  tool_name <- data$params$name
  args <- data$params$arguments

  # HACK for btw_tool_env_describe_environment. In the JSON, it will have
  # `"items": []`, and that translates to an empty list, but we want NULL.
  if (tool_name == "btw_tool_env_describe_environment") {
    if (identical(args$items, list())) {
      args$items <- NULL
    }
  }

  args <- lapply(args, function(x) {
    if (is.list(x) && is.null(names(x))) {
      unlist(x, use.names = FALSE)
    } else {
      x
    }
  })

  tryCatch(
    as_tool_call_result(data, do.call(data$tool, args)),
    error = function(e) {
      jsonrpc_response(
        data$id,
        error = list(code = -32603, message = conditionMessage(e))
      )
    }
  )
}
