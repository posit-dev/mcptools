set_server_tools <- function(
  x,
  session_tools = TRUE,
  x_arg = caller_arg(x),
  call = caller_env()
) {
  if (is.null(x)) {
    if (session_tools) {
      the$server_tools <- c(list(list_r_sessions_tool, select_r_session_tool))
      return()
    } else {
      cli::cli_abort("No tools selected to serve.", call = call)
    }
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

  if (!is.list(x)) {
    x <- list(x)
  }

  if (!all(vapply(x, inherits, logical(1), "ellmer::ToolDef"))) {
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
       reserved by {.pkg mcptools}.",
      call = call
    )
  }

  if (session_tools) {
    x <- c(
      x,
      list(
        list_r_sessions_tool,
        select_r_session_tool
      )
    )
  }
  the$server_tools <- x
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
# to discover R sessions which have called `mcptools::mcp_session()`. They
# are "model-facing" rather than user-facing.
list_r_sessions <- function() {
  probe <- probe_sessions()
  sort(vapply(probe$sessions, function(s) s$description, character(1)))
}

list_r_sessions_description <- paste(
  "List the R sessions that are available to access.",
  "R sessions which have run `mcptools::mcp_session()` will appear here.",
  "In the output, start each session with 'Session #' and do NOT otherwise",
  "prefix any index numbers to the output.",
  "Given the output of this tool, report the sessions to the user.",
  "Do NOT make a choice of R session based on the results of the tool",
  "and call select_r_session unless the user asks you to specifically."
)

list_r_sessions_tool <- ellmer::tool(
  fun = list_r_sessions,
  description = list_r_sessions_description
)

select_r_session <- function(session) {
  dial_session(session)
  sprintf("Selected session %d successfully.", session)
}

select_r_session_description <- paste(
  "Choose the R session of interest.",
  "Use the `list_r_sessions` tool to discover potential sessions.",
  "In general, **do not use this tool unless asked to select a specific R",
  "session**; the server automatically connects to the R session that shares",
  "its working directory or, failing that, to the only running session.",
  "When several sessions are running and none matches, tools execute in a",
  "fresh R process rather than in one of the user's sessions.",
  "Do not call this tool immediately after calling list_r_sessions",
  "unless you've been asked to select an R session and haven't yet",
  "called list_r_sessions.",
  "Your choice of session will persist after the tool is called; only",
  "call this tool more than once if you need to switch between sessions."
)

select_r_session_tool <- ellmer::tool(
  fun = select_r_session,
  description = select_r_session_description,
  arguments = list(
    session = ellmer::type_integer("The R session number to select.")
  )
)

# The server connects to a session lazily, at tool-call time, so that sessions
# started after the server (e.g. via .Rprofile) are still discoverable. While
# unconnected, every session-bound call re-runs discovery: prefer the session
# whose working directory matches the server's (per-project clients like
# Positron launch the server in the project directory), else a sole live
# session. With several sessions and no match there is no safe guess, so stay
# unconnected and let the call execute in the server process (#36) until the
# client selects a session explicitly.
ensure_session_connection <- function() {
  if (nanonext::stat(the$server_socket, "pipes") > 0L) {
    return(TRUE)
  }

  slot <- discover_session_slot()
  if (is.null(slot)) {
    return(FALSE)
  }

  dial_session(slot, autostart = NA)
  nanonext::stat(the$server_socket, "pipes") > 0L
}

discover_session_slot <- function(wd = getwd()) {
  probe <- probe_sessions()

  slots <- vapply(probe$sessions, function(s) s$slot, integer(1))
  wds <- vapply(
    probe$sessions,
    function(s) s$wd %||% NA_character_,
    character(1)
  )
  matches <- which(!is.na(wds) & wds == wd)
  if (length(matches) == 1L) {
    return(slots[matches])
  }

  # `live` comes from dial success, which a busy session still provides even
  # though it can't answer the probe, so a sole busy session is connectable
  if (length(probe$live) == 1L) {
    return(probe$live[1L])
  }

  NULL
}

# Dial every claimed slot and ask each live session to identify itself.
# Returns `live`, the slots which accepted the dial, and `sessions`, a record
# per probe reply: `slot`, `wd` (NULL for sessions predating structured
# replies), and `description` (the display string for list_r_sessions()).
# Busy sessions appear in `live` but not in `sessions`.
probe_sessions <- function() {
  sock <- nanonext::socket("poly")
  on.exit(nanonext::reap(sock))
  cv <- nanonext::cv()
  monitor <- nanonext::monitor(sock, cv)

  live <- integer()
  for (i in seq_len(1024L)) {
    rc <- nanonext::dial(
      sock,
      url = sprintf("%s%d", the$socket_url, i),
      autostart = NA,
      fail = "none"
    )
    if (nanonext::is_error_value(rc)) {
      if (i > 8L) {
        break
      }
    } else {
      live <- c(live, i)
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
  results <- nanonext::collect_aio_(res)

  # a timed-out probe surfaces as an integer error code, not a session string
  replies <- Filter(is.character, results)
  list(live = live, sessions = lapply(replies, parse_session_reply))
}

parse_session_reply <- function(reply) {
  parsed <- tryCatch(jsonlite::parse_json(reply), error = function(e) NULL)
  if (is.list(parsed) && is_string(parsed$description)) {
    return(list(
      slot = as.integer(parsed$session %||% NA_integer_),
      wd = parsed$wd,
      description = parsed$description
    ))
  }

  # a display-string reply from a session predating structured metadata still
  # carries its slot as the numeric prefix
  list(
    slot = suppressWarnings(as.integer(sub("^(\\d+):.*$", "\\1", reply))),
    wd = NULL,
    description = reply
  )
}

# Reap any existing dialer before dialing anew: a leftover dialer from a dead
# session would redial its old slot if a new session claims it, leaving the
# server connected to two sessions at once.
dial_session <- function(slot, ...) {
  dialer <- the$server_socket[["dialer"]]
  if (!is.null(dialer)) {
    nanonext::reap(dialer[[1L]])
    attr(the$server_socket, "dialer") <- NULL
  }

  nanonext::dial(
    the$server_socket,
    url = sprintf("%s%d", the$socket_url, slot),
    ...,
    fail = "none"
  )
}

get_mcptools_tools <- function() {
  # must be called inside of the server session
  res <- the$server_tools
  set_names(res, vapply(res, \(x) x@name, character(1)))
}

get_mcptools_tools_as_json <- function(
  protocol_version = the$protocol_version %||% latest_protocol_version
) {
  tools <- lapply(
    unname(get_mcptools_tools()),
    tool_as_json,
    protocol_version = protocol_version
  )

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
