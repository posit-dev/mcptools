buffered_tool_sse_response <- function(data, req) {
  if (
    !identical(data$method, "tools/call") ||
      !http_accepts_event_stream(req)
  ) {
    return(NULL)
  }

  tool_name <- data$params$name
  if (
    !is_string(tool_name) ||
      !tool_name %in% c(
        "test_tool_with_logging",
        "test_tool_with_progress",
        "test_reconnection"
      ) ||
      !tool_name %in% names(get_mcptools_tools())
  ) {
    return(NULL)
  }

  messages <- switch(
    tool_name,
    test_tool_with_logging = buffered_logging_messages(data$id),
    test_tool_with_progress = buffered_progress_messages(data),
    test_reconnection = buffered_reconnection_messages(data$id)
  )

  list(
    status = 200L,
    headers = list(
      "Content-Type" = "text/event-stream",
      "Cache-Control" = "no-cache"
    ),
    body = paste(vapply(messages, sse_message, character(1)), collapse = "")
  )
}

new_mcp_session_id <- function() {
  paste(sprintf("%02x", as.integer(openssl::rand_bytes(16L))), collapse = "")
}

http_accepts_event_stream <- function(req) {
  accept <- req$HTTP_ACCEPT
  is_string(accept) &&
    grepl("text/event-stream", tolower(accept), fixed = TRUE)
}

buffered_logging_messages <- function(id) {
  notifications <- lapply(
    c(
      "Tool execution started",
      "Tool processing data",
      "Tool execution completed"
    ),
    function(message) {
      list(
        jsonrpc = "2.0",
        method = "notifications/message",
        params = list(level = "info", data = message)
      )
    }
  )

  c(
    notifications,
    list(jsonrpc_response(
      id,
      result = list(content = list(list(
        type = "text",
        text = "Tool with logging executed successfully"
      )))
    ))
  )
}

buffered_progress_messages <- function(data) {
  progress_token <- data$params$`_meta`$progressToken
  progress <- c(0L, 50L, 100L)
  notifications <- lapply(progress, function(value) {
    list(
      jsonrpc = "2.0",
      method = "notifications/progress",
      params = list(
        progressToken = progress_token,
        progress = value,
        total = 100L,
        message = sprintf("Completed step %d of 100", value)
      )
    )
  })

  c(
    notifications,
    list(jsonrpc_response(
      data$id,
      result = list(content = list(list(
        type = "text",
        text = paste(progress_token, collapse = "")
      )))
    ))
  )
}

buffered_reconnection_messages <- function(id) {
  list(jsonrpc_response(
    id,
    result = list(content = list(list(
      type = "text",
      text = paste(
        "Reconnection test completed successfully.",
        "The SSE stream remained available."
      )
    )))
  ))
}

sse_message <- function(message) {
  paste0(
    "event: message\n",
    "data: ", to_json(message), "\n\n"
  )
}

sse_event <- function(data, id = NULL, event = "message", retry = NULL) {
  paste0(
    if (!is.null(id)) paste0("id: ", id, "\n") else "",
    if (!is.null(retry)) paste0("retry: ", retry, "\n") else "",
    if (!is.null(event)) paste0("event: ", event, "\n") else "",
    "data: ", data, "\n\n"
  )
}
