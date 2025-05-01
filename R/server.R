#' Model context protocol for your R session
#'
#' @description
#' Together, these functions implement a model context protocol server for your
#' R session.
#'
#' @section Configuration:
#'
#' [mcp_proxy()] should be configured with the MCP clients via the `Rscript`
#' command. For example, to use with Claude Desktop, paste the following in your
#' Claude Desktop configuration (on macOS, at
#' `file.edit("~/Library/Application Support/Claude/claude_desktop_config.json")`):
#'
#' ```json
#' {
#'   "mcpServers": {
#'     "r-acquaint": {
#'       "command": "Rscript",
#'       "args": ["-e", "acquaint::mcp_proxy()"]
#'     }
#'   }
#' }
#' ```
#'
#' Or, to use with Claude Code, you might type in a terminal:
#'
#' ```bash
#' claude mcp add -s "user" r-acquaint Rscript -e "acquaint::mcp_proxy()"
#' ```
#'
#' **mcp_proxy() is not intended for interactive use.**
#'
#' The proxy interfaces with the MCP client on behalf of the server hosted in
#' your R session. **Use [mcp_serve()] to start the MCP server in your R session.**
#' Place a call to `acquaint::mcp_serve()` in your `.Rprofile`, perhaps with
#' `usethis::edit_r_profile()`, to start a server for your R session every time
#' you start R.
#'
#' @examples
#' if (interactive()) {
#' mcp_serve()
#' }
#'
#' @name mcp
#' @export
mcp_serve <- function() {
  # HACK: If a server is already running in one session via `.Rprofile`,
  # `mcp_serve()` will be called again when the client runs the command
  # Rscript -e "acquaint::mcp_serve()" and the existing server will be wiped.
  # Returning early in this case allows for the desired R session server to be
  # running already before the client initiates the proxy.
  if (!interactive()) {
    return(invisible())
  }

  the$server_socket <- nanonext::socket("poly")
  i <- 1L
  suppressWarnings(
    repeat {
      nanonext::listen(the$server_socket, url = sprintf("%s%d", acquaint_socket, i)) || break
      i <- i + 1L
    }
  )

  schedule_handle_message_from_proxy()
}

handle_message_from_proxy <- function(msg) {
  pipe <- the$raio[["aio"]]
  schedule_handle_message_from_proxy()

  # cat("RECV :", msg, "\n", sep = "", file = stderr())
  data <- jsonlite::parse_json(msg)

  if (data$method == "tools/call") {
    name <- data$params$name
    fn <- getNamespace("btw")[[name]]
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

    body <- jsonrpc_response(
      data$id,
      list(
        content = list(
          list(
            type = "text",
            text = paste(tool_call_result, collapse = "\n")
          )
        ),
        isError = FALSE
      )
    )
  } else {
    body <- jsonrpc_response(
      data$id,
      error = list(code = -32601, message = "Method not found")
    )
  }
  # cat("SEND:", to_json(body), "\n", sep = "", file = stderr())

  # TODO: consider if better / more robust using synchronous sends
  the$saio <- nanonext::send_aio(
    the$server_socket,
    to_json(body),
    mode = "raw",
    pipe = pipe
  )
}

schedule_handle_message_from_proxy <- function() {
  the$raio <- nanonext::recv_aio(the$server_socket, mode = "string")
  promises::as.promise(the$raio)$then(handle_message_from_proxy)$catch(function(e) {
    print(e)
  })
}

# Create a jsonrpc-structured response object.


# Given a vector or list, drop all the NULL items in it
drop_nulls <- function(x) {
  x[!vapply(x, is.null, FUN.VALUE=logical(1))]
}
