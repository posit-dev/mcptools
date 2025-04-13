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

  # TODO: This only works with one active R session. If there's some other R
  # session running with a server, `startServer` will error out. Maybe this
  # should be based on an envvar?
  if (env_has(acquaint_env, "active_server")) {
    httpuv::stopServer(env_get(acquaint_env, "active_server"))
  }

  s <- httpuv::startServer(
    host = "127.0.0.1",
    port = acquaint_port(),
    app = list(
      call = function(req) {
        mcp_serve_impl(req)
      }
    )
  )

  env_bind(acquaint_env, active_server = s)

  s
}

mcp_serve_impl <- function(req) {
  req_body <- rawToChar(req$rook.input$read())

  # In RStudio, content logged to stderr will show in red.
  # cat(req_body, file=stderr())
  data <- jsonlite::fromJSON(req_body)
  # cat(paste(capture.output(str(data)), collapse="\n"), file=stderr())

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

    body <- jsonrpc_response_server(
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
    body <- jsonrpc_response_server(
      data$id,
      error = list(code = -32601, message = "Method not found")
    )
  }
  # cat(to_json(body), file = stderr())

  # cat("Request received at ", format(Sys.time(), "%H:%M:%S.%OS3\n"), file=stderr())

  list(
    status = 200L,
    headers = list('Content-Type' = 'application/json'),
    body = to_json(body)
  )
}

# Create a jsonrpc-structured response object.
jsonrpc_response_server <- function(id, result = NULL, error = NULL) {
  if (!xor(is.null(result), is.null(error))) {
    warning("Either `result` or `error` must be provided, but not both.")
  }

  drop_nulls(list(
    jsonrpc = "2.0",
    id = id,
    result = result,
    error = error
  ))
}

# Given a vector or list, drop all the NULL items in it
drop_nulls <- function(x) {
  x[!vapply(x, is.null, FUN.VALUE=logical(1))]
}
