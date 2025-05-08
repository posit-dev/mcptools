#' Model context protocol for your R session
#'
#' @description
#' Together, these functions implement a model context protocol server for your
#' R session.
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
#'     "r-acquaint": {
#'       "command": "Rscript",
#'       "args": ["-e", "acquaint::mcp_server()"]
#'     }
#'   }
#' }
#' ```
#'
#' Or, to use with Claude Code, you might type in a terminal:
#'
#' ```bash
#' claude mcp add -s "user" r-acquaint Rscript -e "acquaint::mcp_server()"
#' ```
#'
#' **mcp_server() is not intended for interactive use.**
#'
#' The server interfaces with the MCP client on behalf of your R session.
#' **Use [mcp_session()] to make your R session available to the server.**
#' Place a call to `acquaint::mcp_session()` in your `.Rprofile`, perhaps with
#' `usethis::edit_r_profile()`, to make every interactive R session you start
#' available to the server.
#'
#' @examples
#' if (interactive()) {
#' mcp_session()
#' }
#'
#' @name mcp
#' @export
mcp_session <- function() {
  # HACK: If a session is already available from another session via `.Rprofile`,
  # `mcp_session()` will be called again when the client runs the command
  # Rscript -e "acquaint::mcp_server()" and the existing session connection
  # will be wiped. Returning early in this case allows for the desired R
  # session to be running already before the client initiates the server.
  if (!interactive()) {
    return(invisible())
  }

  the$session_socket <- nanonext::socket("poly")
  i <- 1L
  suppressWarnings(
    while (i < 1024L) {
      # prevent indefinite loop
      nanonext::listen(
        the$session_socket,
        url = sprintf("%s%d", acquaint_socket, i)
      ) ||
        break
      i <- i + 1L
    }
  )
  the$session <- i

  schedule_handle_message_from_server()
}

handle_message_from_server <- function(msg) {
  pipe <- nanonext::pipe_id(the$raio)
  schedule_handle_message_from_server()

  # cat("RECV :", msg, "\n", sep = "", file = stderr())
  if (!nzchar(msg)) {
    return(
      nanonext::send_aio(
        the$session_socket,
        describe_session(),
        mode = "raw",
        pipe = pipe
      )
    )
  }
  data <- jsonlite::parse_json(msg)

  if (data$method == "tools/call") {
    name <- data$params$name

    fn <- get_acquaint_tools()[[name]]
    args <- data$params$arguments

    # HACK for btw_tool_env_describe_environment. In the JSON, it will have
    # `"items": []`, and that translates to an empty list, but we want NULL.
    if (name == "btw_tool_env_describe_environment") {
      if (identical(args$items, list())) {
        args$items <- NULL
      }
    }

    tool_call_result <- do.call(fn, args)
    # cat(paste(capture.output(str(body)), collapse="\n"), file=stderr())

    body <- as_tool_call_result(data, tool_call_result)
  } else {
    body <- jsonrpc_response(
      data$id,
      error = list(code = -32601, message = "Method not found")
    )
  }
  # cat("SEND:", to_json(body), "\n", sep = "", file = stderr())

  nanonext::send_aio(
    the$session_socket,
    to_json(body),
    mode = "raw",
    pipe = pipe
  )
}

as_tool_call_result <- function(data, result) {
  jsonrpc_response(
    data$id,
    list(
      content = list(
        list(
          type = "text",
          text = paste(result, collapse = "\n")
        )
      ),
      isError = FALSE
    )
  )
}

schedule_handle_message_from_server <- function() {
  the$raio <- nanonext::recv_aio(the$session_socket, mode = "string")
  promises::as.promise(the$raio)$then(handle_message_from_server)$catch(
    function(
      e
    ) {
      print(e)
    }
  )
}

# Create a jsonrpc-structured response object.

# Given a vector or list, drop all the NULL items in it
drop_nulls <- function(x) {
  x[!vapply(x, is.null, FUN.VALUE = logical(1))]
}

# Enough information for the user to be able to identify which
# session is which when using `list_r_sessions()` (#18)
describe_session <- function() {
  sprintf("%d: %s (%s)", the$session, basename(getwd()), infer_ide())
}

infer_ide <- function() {
  first_cmd_arg <- commandArgs()[1]
  switch(
    first_cmd_arg,
    ark = "Positron",
    RStudio = "RStudio",
    first_cmd_arg
  )
}
