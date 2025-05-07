# These two functions are supplied to the client as tools and allow the client
# to discover R sessions which have called `acquaint::mcp_host()`. They
# are "model-facing" rather than user-facing.
list_r_sessions <- function() {
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
  sort(as.character(nanonext::collect_aio_(res)))
}

list_r_sessions_tool <-
  ellmer::tool(
    .fun = list_r_sessions,
    .description = paste(
      "List the R sessions that are available to access.",
      "R sessions which have run `acquaint::mcp_host()` will appear here.",
      "In general, do not use this tool unless asked to list or",
      "select a specific R session.",
      "Given the output of this tool, report the users to the user.",
      "Do NOT make a choice of R session based on the results of the tool",
      "and call select_r_session unless the user asks you to specifically."
    )
  )

select_r_session <- function(i) {
  lapply(the$server_socket[["dialer"]], nanonext::reap)
  attr(the$server_socket, "dialer") <- NULL
  nanonext::dial(
    the$server_socket,
    url = sprintf("%s%d", acquaint_socket, as.integer(i))
  )
  paste0("Selected session ", i, " successfully.")
}

select_r_session_tool <-
  ellmer::tool(
    .fun = select_r_session,
    .description = paste(
      "Choose the R session host of interest.",
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
    i = ellmer::type_integer("The index of the host session to select.")
  )

.acquaint_tools <- list(list_r_sessions_tool, select_r_session_tool)
