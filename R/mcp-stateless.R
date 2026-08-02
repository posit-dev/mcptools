stateless_protocol_version <- "2026-07-28"

stateless_removed_methods <- c(
  "initialize",
  "ping",
  "logging/setLevel",
  "resources/subscribe",
  "resources/unsubscribe"
)

is_stateless_http_request <- function(req, data) {
  if (!is.null(req$HTTP_MCP_SESSION_ID)) {
    return(FALSE)
  }

  meta <- data$params$`_meta`
  has_stateless_meta <- !is.null(
    meta$`io.modelcontextprotocol/protocolVersion`
  ) || !is.null(
    meta$`io.modelcontextprotocol/clientCapabilities`
  )
  identical(req$HTTP_MCP_PROTOCOL_VERSION, stateless_protocol_version) ||
    has_stateless_meta
}

handle_stateless_http_post <- function(req, data) {
  validation_error <- stateless_request_validation_error(req, data)
  if (!is.null(validation_error)) {
    return(validation_error)
  }

  if (is.null(data$id)) {
    dispatch_mcp_notification(
      data,
      stateless_protocol_version,
      transport = "http"
    )
    return(list(
      status = 202L,
      headers = list("Content-Type" = "application/json"),
      body = ""
    ))
  }

  if (data$method %in% stateless_removed_methods) {
    return(stateless_method_not_found(data$id))
  }

  if (
    identical(data$method, "tools/call") &&
      identical(data$params$name, "test_missing_capability") &&
      is.null(stateless_client_capabilities(data)$sampling)
  ) {
    return(stateless_jsonrpc_http_error(
      data$id,
      status = 400L,
      code = -32021L,
      message = "Missing required client capability",
      error_data = list(
        requiredCapabilities = list(sampling = named_list())
      )
    ))
  }

  if (identical(data$method, "server/discover")) {
    response <- jsonrpc_response(
      data$id,
      result = stateless_discover_result()
    )
  } else {
    response <- stateless_mrtr_response(data)
    if (is.null(response)) {
      response <- handle_http_request_message(
        data,
        protocol_version = stateless_protocol_version
      )
    }
    response <- stateless_stamp_response(response, data$method)
  }

  if (!is.null(response$error) && isTRUE(response$error$code == -32601)) {
    return(stateless_method_not_found(data$id))
  }

  if (!is.null(response$error) && isTRUE(response$error$code == -32021)) {
    return(list(
      status = 400L,
      headers = list("Content-Type" = "application/json"),
      body = to_json(response)
    ))
  }

  if (identical(data$method, "tools/call")) {
    return(stateless_tool_sse_response(data, response))
  }

  list(
    status = 200L,
    headers = list("Content-Type" = "application/json"),
    body = to_json(response)
  )
}

stateless_request_validation_error <- function(req, data) {
  header_version <- req$HTTP_MCP_PROTOCOL_VERSION
  if (!is_string(header_version) || !nzchar(header_version)) {
    return(stateless_jsonrpc_http_error(
      data$id,
      status = 400L,
      code = -32020L,
      message = "Missing MCP-Protocol-Version header"
    ))
  }

  meta <- data$params$`_meta`
  meta_version <- meta$`io.modelcontextprotocol/protocolVersion`
  client_capabilities <- meta$`io.modelcontextprotocol/clientCapabilities`
  if (
    !is.list(meta) ||
      !is_string(meta_version) ||
      !is.list(client_capabilities)
  ) {
    return(stateless_jsonrpc_http_error(
      data$id,
      status = 400L,
      code = -32602L,
      message = "Invalid params: stateless request metadata is incomplete"
    ))
  }

  if (!identical(header_version, meta_version)) {
    return(stateless_jsonrpc_http_error(
      data$id,
      status = 400L,
      code = -32020L,
      message = "MCP-Protocol-Version header does not match request metadata"
    ))
  }

  if (!identical(meta_version, stateless_protocol_version)) {
    return(stateless_jsonrpc_http_error(
      data$id,
      status = 400L,
      code = -32022L,
      message = "Unsupported protocol version",
      error_data = list(
        supported = supported_protocol_versions,
        requested = meta_version
      )
    ))
  }

  header_error <- stateless_standard_header_error(req, data)
  if (!is.null(header_error)) {
    return(header_error)
  }

  stateless_custom_header_error(req, data)
}

stateless_standard_header_error <- function(req, data) {
  if (
    !is_string(req$HTTP_MCP_METHOD) ||
      !identical(req$HTTP_MCP_METHOD, data$method)
  ) {
    return(stateless_header_mismatch(
      data$id,
      "Mcp-Method header does not match the JSON-RPC method"
    ))
  }

  expected_name <- stateless_request_name(data)
  if (
    !is.null(expected_name) &&
      (
        !is_string(req$HTTP_MCP_NAME) ||
          !identical(req$HTTP_MCP_NAME, expected_name)
      )
  ) {
    return(stateless_header_mismatch(
      data$id,
      "Mcp-Name header does not match the request parameters"
    ))
  }

  NULL
}

stateless_request_name <- function(data) {
  if (data$method %in% c("tools/call", "prompts/get")) {
    return(data$params$name)
  }
  if (identical(data$method, "resources/read")) {
    return(data$params$uri)
  }
  NULL
}

stateless_custom_header_error <- function(req, data) {
  if (!identical(data$method, "tools/call")) {
    return(NULL)
  }

  tool_name <- data$params$name
  if (!is_string(tool_name) || !tool_name %in% names(get_mcptools_tools())) {
    return(NULL)
  }

  schema <- attr(
    get_mcptools_tools()[[tool_name]],
    "mcp_input_schema",
    exact = TRUE
  )
  properties <- schema$properties
  if (!is.list(properties) || !length(properties)) {
    return(NULL)
  }

  arguments <- data$params$arguments %||% named_list()
  for (name in names(properties)) {
    suffix <- properties[[name]][["x-mcp-header"]]
    if (
      !is_string(suffix) ||
        is.null(arguments[[name]])
    ) {
      next
    }

    rook_name <- paste0(
      "HTTP_MCP_PARAM_",
      toupper(gsub("-", "_", suffix, fixed = TRUE))
    )
    header_value <- req[[rook_name]]
    if (!is_string(header_value)) {
      return(stateless_header_mismatch(
        data$id,
        paste0("Missing Mcp-Param-", suffix, " header")
      ))
    }

    decoded <- stateless_decode_header_value(header_value)
    if (!isTRUE(decoded$valid)) {
      return(stateless_header_mismatch(data$id, decoded$message))
    }

    body_value <- arguments[[name]]
    if (
      length(body_value) != 1L ||
        !identical(as.character(body_value), decoded$value)
    ) {
      return(stateless_header_mismatch(
        data$id,
        paste0("Mcp-Param-", suffix, " header does not match the body")
      ))
    }
  }

  NULL
}

stateless_decode_header_value <- function(value) {
  wrapped <- startsWith(value, "=?base64?") && endsWith(value, "?=")
  if (!wrapped) {
    return(list(valid = TRUE, value = value))
  }

  payload <- substr(value, 10L, nchar(value) - 2L)
  valid_syntax <- nzchar(payload) &&
    nchar(payload) %% 4L == 0L &&
    grepl("^[A-Za-z0-9+/]*={0,2}$", payload)
  if (!valid_syntax) {
    return(list(
      valid = FALSE,
      message = "Invalid Base64 Mcp-Param header value"
    ))
  }

  decoded <- tryCatch(
    rawToChar(openssl::base64_decode(payload)),
    error = function(err) NULL
  )
  if (is.null(decoded)) {
    return(list(
      valid = FALSE,
      message = "Invalid Base64 Mcp-Param header value"
    ))
  }

  list(valid = TRUE, value = decoded)
}

stateless_header_mismatch <- function(id, message) {
  stateless_jsonrpc_http_error(
    id,
    status = 400L,
    code = -32020L,
    message = message
  )
}

stateless_jsonrpc_http_error <- function(
  id,
  status,
  code,
  message,
  error_data = NULL
) {
  list(
    status = status,
    headers = list("Content-Type" = "application/json"),
    body = to_json(jsonrpc_response(
      id,
      error = drop_nulls(list(
        code = code,
        message = message,
        data = error_data
      ))
    ))
  )
}

stateless_method_not_found <- function(id) {
  stateless_jsonrpc_http_error(
    id,
    status = 404L,
    code = -32601L,
    message = "Method not found"
  )
}

stateless_client_capabilities <- function(data) {
  data$params$`_meta`$`io.modelcontextprotocol/clientCapabilities`
}

stateless_discover_result <- function() {
  discovered <- capabilities(stateless_protocol_version)$capabilities
  discovered$logging <- NULL
  discovered$tools$listChanged <- TRUE
  discovered$prompts$listChanged <- TRUE
  discovered$resources <- named_list()

  list(
    resultType = "complete",
    supportedVersions = supported_protocol_versions,
    capabilities = discovered,
    `_meta` = list(
      `io.modelcontextprotocol/serverInfo` = list(
        name = "R mcptools stateless server",
        version = "0.0.1"
      )
    ),
    ttlMs = 0L,
    cacheScope = "private"
  )
}

stateless_stamp_response <- function(response, method) {
  if (is.null(response$result)) {
    return(response)
  }

  if (is.null(response$result$resultType)) {
    response$result$resultType <- "complete"
  }
  hint <- stateless_cache_hint(method)
  if (!is.null(hint)) {
    response$result$ttlMs <- hint$ttlMs
    response$result$cacheScope <- hint$cacheScope
  }
  response
}

stateless_cache_hint <- function(method) {
  switch(
    method,
    `server/discover` = list(ttlMs = 0L, cacheScope = "private"),
    `tools/list` = list(ttlMs = 300000L, cacheScope = "public"),
    `prompts/list` = list(ttlMs = 300000L, cacheScope = "public"),
    `resources/list` = list(ttlMs = 300000L, cacheScope = "public"),
    `resources/templates/list` = list(
      ttlMs = 300000L,
      cacheScope = "public"
    ),
    `resources/read` = list(ttlMs = 300000L, cacheScope = "private"),
    NULL
  )
}

stateless_tool_sse_response <- function(data, response) {
  messages <- if (identical(data$params$name, "test_tool_with_progress")) {
    buffered_progress_messages(data)
  } else {
    list(response)
  }
  messages <- lapply(messages, stateless_stamp_response, method = data$method)

  list(
    status = 200L,
    headers = list(
      "Content-Type" = "text/event-stream",
      "Cache-Control" = "no-cache"
    ),
    body = paste(vapply(messages, sse_message, character(1)), collapse = "")
  )
}
