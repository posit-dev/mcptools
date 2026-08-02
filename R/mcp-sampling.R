mcp_sampling_request <- function(data, id) {
  list(
    jsonrpc = "2.0",
    id = id,
    method = "sampling/createMessage",
    params = list(
      messages = list(list(
        role = "user",
        content = list(
          type = "text",
          text = data$params$arguments$prompt
        )
      )),
      maxTokens = 100L
    )
  )
}

mcp_sampling_tool_response <- function(response, tool_request_id) {
  if (!is.null(response$error)) {
    return(mcp_server_request_tool_error(
      tool_request_id,
      response$error$message %||% "Sampling request failed"
    ))
  }

  content <- response$result$content
  text <- if (is.list(content) && identical(content$type, "text")) {
    content$text
  } else {
    to_json(content)
  }

  jsonrpc_response(
    tool_request_id,
    result = list(content = list(list(
      type = "text",
      text = paste0("LLM response: ", text)
    )))
  )
}
