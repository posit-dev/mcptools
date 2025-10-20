#' @rdname server
#' @export
mcp_session <- function() {

  the$session_socket <- nanonext::socket("poly")
  i <- 1L
  while (i < 1024L) {
    # prevent indefinite loop
    nanonext::listen(
      the$session_socket,
      url = sprintf("%s%d", the$socket_url, i),
      fail = "none"
    ) ||
      break
    i <- i + 1L
  }
  the$session <- i
  schedule_handle_message_from_server()

  invisible(the$session_socket)
}

handle_message_from_server <- function(data) {
  pipe <- nanonext::pipe_id(the$raio)
  schedule_handle_message_from_server()

  if (length(data) == 0) {
    return(
      nanonext::send_aio(
        the$session_socket,
        describe_session(),
        mode = "raw",
        pipe = pipe
      )
    )
  }

  if (data$method == "tools/call") {
    body <- execute_tool_call(data)
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
  is_error <- FALSE
  format_result <- function(x) paste(x, collapse = "\n")
  
  if (inherits(result, "ellmer::ContentToolResult")) {
    is_error <- !is.null(result@error)
    format_result <- asNamespace("ellmer")[["tool_string"]] %||% format_result
  }
  
  jsonrpc_response(
    data$id,
    list(
      content = list(
        list(
          type = "text",
          text = format_result(result)
        )
      ),
      isError = is_error
    )
  )
}

schedule_handle_message_from_server <- function() {
  the$raio <- nanonext::recv_aio(the$session_socket, mode = "serial")
  promises::as.promise(the$raio)$then(handle_message_from_server)$catch(
    \(e) {
      # no op but ensures promise is never rejected
    }
  )
}

# Create a jsonrpc-structured response object.

# Given a vector or list, drop all the NULL items in it
drop_nulls <- function(x) {
  is_null <- vapply(x, is.null, FUN.VALUE = logical(1))
  keep_id <- rep(FALSE, length(x))
  if (!is.null(names(x))) {
    keep_id <- names(x) == "id"
  }
  x[!is_null | keep_id]
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

# assign NULL for mocking in testing
basename <- NULL
getwd <- NULL
commandArgs <- NULL
