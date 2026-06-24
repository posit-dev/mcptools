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

  if (inherits(result, "ellmer::ContentToolResult")) {
    is_error <- !is.null(result@error)
  }

  jsonrpc_response(
    data$id,
    list(
      content = as_mcp_content(result),
      isError = is_error
    )
  )
}

as_mcp_content <- function(result) {
  if (inherits(result, "ellmer::ContentToolResult")) {
    value <- result@value
    if (has_mcp_content(value)) {
      return(as_mcp_content(value))
    }

    return(list(as_mcp_text_content(result)))
  }

  if (is_mcp_content(result)) {
    return(list(as_mcp_content_block(result)))
  }

  if (is.list(result) && has_mcp_content(result)) {
    return(unname(unlist(lapply(result, as_mcp_content), recursive = FALSE)))
  }

  list(as_mcp_text_content(result))
}

as_mcp_content_block <- function(result) {
  if (inherits(result, "ellmer::ContentImageInline")) {
    return(list(type = "image", data = result@data, mimeType = result@type))
  }

  if (inherits(result, "ellmer::ContentText")) {
    return(list(type = "text", text = result@text))
  }

  as_mcp_text_content(result)
}

as_mcp_text_content <- function(result) {
  list(type = "text", text = format_mcp_text(result))
}

format_mcp_text <- function(result) {
  if (inherits(result, "ellmer::ContentToolResult")) {
    format_result <- asNamespace("ellmer")[["tool_string"]] %||%
      format_default_result
    return(format_result(result))
  }

  format_default_result(result)
}

format_default_result <- function(result) {
  paste(result, collapse = "\n")
}

has_mcp_content <- function(result) {
  if (is_mcp_content(result)) {
    return(TRUE)
  }

  if (is.list(result)) {
    return(any(vapply(result, has_mcp_content, logical(1))))
  }

  FALSE
}

is_mcp_content <- function(result) {
  inherits(result, "ellmer::ContentImageInline") ||
    inherits(result, "ellmer::ContentText")
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
