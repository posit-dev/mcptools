#' Set the tools available to run in your R session
#'
#' @description
#' By default, acquaint supplies tools from [btw::btw_tools()] to allow clients
#' to peruse package documentation, inspect your global environment, and query
#' session details. This function allows you register any tools created with
#' [ellmer::tool()] instead.
#'
#' A call to this function must be placed in your `.Rprofile` and the client
#' (i.e. Claude Desktop or Claude Code) restarted in order for the new tools
#' to be registered.
#'
#' acquaint will always register the tools "list_r_sessions" and
#' "select_r_session" in addition to the tools provided here; those tool names
#' are thus reserved for the package.
#'
#' @param x A list of tools created with [ellmer::tool()]. Any list that could
#' be passed to `chat$set_tools()` can be passed here.
#'
#' @returns
#' `x`, invisibly. Called for side effects. The function will error if `x` is
#' not a list of `ellmer::ToolDef` objects or if any tool name is one of the
#' reserved names "list_r_sessions" or "select_r_session".
#'
#' @examples
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
#' # supply only one tool, tool_rnorm
#' set_acquaint_tools(list(tool_rnorm))
#'
#' # supply both tool_rnorm and `btw_tools()`
#' set_acquaint_tools(c(list(tool_rnorm), btw::btw_tools()))
#' @export
set_acquaint_tools <- function(x) {
  check_acquaint_tools(x)

  options(.acquaint_tools = x)

  invisible(x)
}

check_acquaint_tools <- function(x, call = caller_env()) {
  if (!is_list(x) || !all(vapply(x, inherits, logical(1), "ellmer::ToolDef"))) {
    msg <- "{.arg x} must be a list of tools created with {.fn ellmer::tool}."
    if (inherits(x, "ellmer::ToolDef")) {
      msg <- c(msg, "i" = "Did you mean to wrap {.arg x} in `list()`?")
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
}

# These two functions are supplied to the client as tools and allow the client
# to discover R sessions which have called `acquaint::mcp_session()`. They
# are "model-facing" rather than user-facing.
list_r_sessions <- function() {
  sock <- nanonext::socket("poly")
  on.exit(nanonext::reap(sock))
  cv <- nanonext::cv()
  monitor <- nanonext::monitor(sock, cv)
  suppressWarnings(
    for (i in seq_len(1024L)) {
      if (
        nanonext::dial(
          sock,
          url = sprintf("%s%d", acquaint_socket, i),
          autostart = NA
        ) &&
          i > 8L
      )
        break
    }
  )
  pipes <- nanonext::read_monitor(monitor)
  res <- lapply(
    pipes,
    function(x) nanonext::recv_aio(sock, mode = "string")
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

select_r_session <- function(i) {
  nanonext::reap(the$server_socket[["dialer"]][[1L]])
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
    i = ellmer::type_integer("The index of the R session to select.")
  )

get_acquaint_tools <- function() {
  res <- c(
    getOption(".acquaint_tools", default = btw::btw_tools()),
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
