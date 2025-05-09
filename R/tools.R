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
    )
      break
  }
  pipes <- nanonext::read_monitor(monitor)
  res <- lapply(
    pipes,
    function(x) nanonext::recv_aio(sock, mode = "string", timeout = 5000L)
  )
  lapply(
    pipes,
    function(x) nanonext::send_aio(sock, "", mode = "raw", pipe = x)
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
  res <- c(
    btw::btw_tools(),
    list(
      list_r_sessions_tool,
      select_r_session_tool
    )
  )
  set_names(res, vapply(res, \(x) x@name, character(1)))
}

get_acquaint_tools_as_json <- function() {
  tools <- lapply(unname(get_acquaint_tools()), tool_as_json)

  compact(tools)
}
