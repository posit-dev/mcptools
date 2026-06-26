# This file implements the client's Streamable HTTP transport.

# client protocol: Streamable HTTP ---------------------------------------------
mcp_transport_http_send <- function(
  transport,
  message,
  expect_response,
  call = caller_env(),
  auth_retry = TRUE,
  reauth = FALSE,
  acquire = TRUE,
  session_retry = TRUE
) {
  mcp_log_json_message("FROM CLIENT: ", message)

  if (expect_response && acquire) {
    mcp_transport_http_acquire_request(transport, call = call)
    on.exit(mcp_transport_http_release_request(transport), add = TRUE)
  }

  mcp_oauth_prepare_token(transport, call = call)
  req <- mcp_transport_http_request(transport, message)
  resp <- if (expect_response) {
    httr2::req_perform_connection(req)
  } else {
    httr2::req_perform(req)
  }
  if (expect_response) {
    on.exit(close(resp), add = TRUE)
  }

  mcp_transport_http_store_session(transport, resp, message = message, call = call)
  status <- httr2::resp_status(resp)

  if (status == 404L && !is.null(transport$session_id)) {
    transport$session_id <- NULL
    transport$protocol_version <- NULL

    # Per the spec, a 404 for a request carrying a session id means the session
    # expired; start a fresh session and retry the original request once. Tool
    # definitions are already materialized, so only the session is re-established.
    if (session_retry && !identical(message$method, "initialize")) {
      mcp_transport_http_reinitialize(transport, call = call)
      return(mcp_transport_http_send(
        transport,
        message,
        expect_response,
        call = call,
        session_retry = FALSE,
        acquire = FALSE
      ))
    }

    cli::cli_abort(
      c(
        "MCP HTTP session expired.",
        i = "Re-run {.fun mcp_tools} to reinitialize the server and refresh tool definitions."
      ),
      class = "mcptools_http_session_expired",
      call = call
    )
  }

  if (status %in% c(401L, 403L)) {
    # First retry authorizes from the challenge (reusing any cached token);
    # if that token is also rejected, retry once more forcing fresh auth.
    if (
      auth_retry &&
        mcp_oauth_authorize_from_challenge(transport, resp, reauth = reauth, call = call)
    ) {
      return(mcp_transport_http_send(
        transport,
        message,
        expect_response,
        call = call,
        auth_retry = !reauth,
        reauth = TRUE,
        acquire = FALSE
      ))
    }

    mcp_abort_http_auth(transport, resp, status, call = call)
  }

  if (status >= 400L) {
    cli::cli_abort(
      c(
        "MCP HTTP request failed.",
        i = "Status: {.val {status}}."
      ),
      call = call
    )
  }

  if (!expect_response) {
    return(invisible(NULL))
  }

  content_type <- httr2::resp_content_type(resp) %||% ""

  if (grepl("text/event-stream", content_type, fixed = TRUE)) {
    return(mcp_transport_http_read_sse(transport, resp, message$id, call = call))
  }

  mcp_transport_http_read_json(resp, message$id, call = call)
}

# Re-run the initialize handshake on a transport whose session expired. The
# sub-requests pass `session_retry = FALSE` so a reinitialization can never
# trigger another nested reinitialization, and `acquire = FALSE` so they reuse
# the active-request guard already held by the in-flight caller.
mcp_transport_http_reinitialize <- function(transport, call = caller_env()) {
  response <- mcp_transport_http_send(
    transport,
    mcp_request_initialize(id = 1L),
    expect_response = TRUE,
    call = call,
    session_retry = FALSE,
    acquire = FALSE
  )
  mcp_transport_store_initialize(transport, response, call = call)

  mcp_transport_http_send(
    transport,
    mcp_request_initialized(),
    expect_response = FALSE,
    call = call,
    session_retry = FALSE
  )

  invisible(transport)
}

# the transport supports a single in-flight response-bearing request; this guard
# turns accidental reentrancy into a clear error rather than a tangled stream.
mcp_transport_http_acquire_request <- function(transport, call = caller_env()) {
  if (!isTRUE(transport$http_request_active)) {
    transport$http_request_active <- TRUE
    return(invisible(TRUE))
  }

  cli::cli_abort(
    c(
      "MCP HTTP transport already has an active request.",
      i = "Concurrent response-bearing requests are not supported."
    ),
    call = call
  )
}

mcp_transport_http_release_request <- function(transport) {
  transport$http_request_active <- FALSE
  invisible(TRUE)
}

mcp_transport_http_request <- function(transport, message) {
  req <- httr2::request(transport$url)
  req <- httr2::req_method(req, "POST")
  req <- httr2::req_body_json(req, message, auto_unbox = TRUE)
  req <- httr2::req_headers(req, Accept = "application/json, text/event-stream")
  req <- mcp_transport_http_headers(req, transport)
  req <- mcp_req_no_error(req)
  mcp_req_timeout(req, transport$timeout)
}

mcp_endpoint_delete_request <- function(transport) {
  req <- httr2::request(transport$url)
  req <- httr2::req_method(req, "DELETE")
  req <- httr2::req_headers(req, Accept = "application/json, text/event-stream")
  req <- mcp_transport_http_headers(req, transport)
  req <- mcp_req_no_error(req)
  mcp_req_timeout(req, transport$timeout)
}

mcp_metadata_get_request <- function(url, timeout = NULL) {
  req <- httr2::request(url)
  req <- mcp_req_no_redirects(req)
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- mcp_req_no_error(req)
  mcp_req_timeout(req, timeout)
}

mcp_dcr_post_request <- function(url, client_metadata, timeout = NULL) {
  req <- httr2::request(url)
  req <- httr2::req_method(req, "POST")
  req <- httr2::req_body_json(req, client_metadata, auto_unbox = TRUE)
  req <- httr2::req_headers(req, Accept = "application/json")
  req <- mcp_req_no_error(req)
  mcp_req_timeout(req, timeout)
}

mcp_req_no_error <- function(req) {
  httr2::req_error(req, is_error = function(resp) FALSE)
}

mcp_req_no_redirects <- function(req) {
  httr2::req_options(req, followlocation = FALSE)
}

mcp_req_timeout <- function(req, timeout = NULL) {
  if (is.null(timeout)) {
    return(req)
  }

  httr2::req_timeout(req, timeout)
}

mcp_transport_http_close <- function(transport, call = caller_env()) {
  if (is.null(transport$session_id)) {
    return(invisible(FALSE))
  }

  req <- mcp_endpoint_delete_request(transport)
  resp <- httr2::req_perform(req)
  status <- httr2::resp_status(resp)

  if (!status %in% c(200L, 202L, 204L, 404L, 405L)) {
    cli::cli_abort(
      c(
        "MCP HTTP session cleanup failed.",
        i = "Status: {.val {status}}."
      ),
      call = call
    )
  }

  transport$session_id <- NULL
  invisible(TRUE)
}

mcp_transport_http_headers <- function(req, transport) {
  headers <- transport$headers
  token <- transport$oauth_token

  if (
    !any(tolower(names(headers)) == "authorization") &&
      !is.null(token$access_token) &&
      nzchar(token$access_token)
  ) {
    headers[["Authorization"]] <- paste("Bearer", token$access_token)
  }

  if (!is.null(transport$session_id)) {
    headers[["MCP-Session-Id"]] <- transport$session_id
  }

  if (!is.null(transport$protocol_version)) {
    headers[["MCP-Protocol-Version"]] <- transport$protocol_version
  }

  if (length(headers) == 0) {
    return(req)
  }

  do.call(httr2::req_headers, c(list(.req = req), as.list(headers)))
}

mcp_transport_http_store_session <- function(
  transport,
  resp,
  message = NULL,
  call = caller_env()
) {
  if (!identical(message$method %||% NULL, "initialize")) {
    return(invisible(transport))
  }

  status <- httr2::resp_status(resp)
  if (status < 200L || status >= 300L) {
    return(invisible(transport))
  }

  session_id <- httr2::resp_header(resp, "mcp-session-id")
  if (!is.null(session_id) && nzchar(session_id)) {
    mcp_validate_http_session_id(session_id, call = call)
    transport$session_id <- session_id
  }

  invisible(transport)
}

mcp_validate_http_session_id <- function(session_id, call = caller_env()) {
  if (grepl("^[!-~]+$", session_id, perl = TRUE)) {
    return(invisible(TRUE))
  }

  cli::cli_abort(
    "MCP HTTP initialize returned an invalid session id.",
    call = call
  )
}

mcp_transport_http_read_json <- function(resp, request_id, call = caller_env()) {
  body <- mcp_transport_http_read_raw(resp)

  if (length(body) == 0L) {
    cli::cli_abort(
      "MCP HTTP request returned no response body.",
      call = call
    )
  }

  body_text <- rawToChar(body)
  mcp_log_json_text("FROM SERVER: ", body_text)

  parsed <- tryCatch(
    jsonlite::parse_json(body_text),
    error = function(err) {
      cli::cli_abort(
        "MCP HTTP response body was not valid JSON.",
        call = call,
        parent = err
      )
    }
  )

  mcp_validate_jsonrpc_response(parsed, request_id, call = call)
}

mcp_transport_http_read_raw <- function(resp) {
  if (!inherits(resp$body, "connection")) {
    return(tryCatch(
      httr2::resp_body_raw(resp),
      error = function(err) raw()
    ))
  }

  body <- raw()
  while (!httr2::resp_stream_is_complete(resp)) {
    chunk <- httr2::resp_stream_raw(resp)
    if (length(chunk) == 0L) {
      break
    }
    body <- c(body, chunk)
  }

  body
}

# Read a POST response delivered as Server-Sent Events, routing any server
# requests or notifications until the JSON-RPC response for `request_id` arrives.
# Stream resumability (Last-Event-ID reconnect) is intentionally unsupported: if
# the stream ends before the response, that is a transport loss.
mcp_transport_http_read_sse <- function(transport, resp, request_id, call = caller_env()) {
  if (!inherits(resp$body, "connection")) {
    events <- mcp_parse_sse_events(rawToChar(httr2::resp_body_raw(resp)))
    for (event in events) {
      routed <- mcp_transport_http_route_sse_event(transport, event, request_id, call = call)
      if (!is.null(routed)) {
        return(routed)
      }
    }

    mcp_sse_transport_loss(
      "MCP HTTP SSE stream ended before the response arrived.",
      call = call
    )
  }

  repeat {
    event <- mcp_resp_stream_sse(resp, call = call)

    if (is.null(event)) {
      if (httr2::resp_stream_is_complete(resp)) {
        mcp_sse_transport_loss(
          "MCP HTTP SSE stream ended before the response arrived.",
          call = call
        )
      }
      next
    }

    routed <- mcp_transport_http_route_sse_event(transport, event, request_id, call = call)
    if (!is.null(routed)) {
      return(routed)
    }
  }
}

mcp_resp_stream_sse <- function(resp, call = caller_env()) {
  tryCatch(
    httr2::resp_stream_sse(resp),
    error = function(err) {
      mcp_sse_transport_loss(
        "MCP HTTP SSE stream disconnected before the response arrived.",
        call = call,
        parent = err
      )
    }
  )
}

mcp_sse_transport_loss <- function(message, call = caller_env(), parent = NULL) {
  cli::cli_abort(
    message,
    class = "mcptools_sse_transport_lost",
    call = call,
    parent = parent
  )
}

mcp_transport_http_route_sse_event <- function(transport, event, request_id, call = caller_env()) {
  if (!nzchar(event$data)) {
    return(NULL)
  }

  mcp_log_json_text("FROM SERVER: ", event$data)

  message <- tryCatch(
    jsonlite::parse_json(event$data),
    error = function(err) {
      cli::cli_abort(
        "MCP HTTP SSE event data was not valid JSON.",
        call = call,
        parent = err
      )
    }
  )

  mcp_client_route_server_message(transport, message, request_id, call = call)
}

mcp_parse_sse_events <- function(text) {
  if (!nzchar(text)) {
    return(list())
  }

  chunks <- strsplit(text, "\\r?\\n\\r?\\n", perl = TRUE)[[1]]
  chunks <- chunks[nzchar(chunks)]

  lapply(chunks, mcp_parse_sse_event)
}

mcp_parse_sse_event <- function(text) {
  lines <- strsplit(text, "\\r?\\n", perl = TRUE)[[1]]
  data <- character()

  for (line in lines) {
    if (!nzchar(line) || startsWith(line, ":")) {
      next
    }

    field_value <- strsplit(line, ":", fixed = TRUE)[[1]]
    field <- field_value[[1]]
    value <- sub("^ ", "", paste(field_value[-1], collapse = ":"))

    if (identical(field, "data")) {
      data <- c(data, value)
    }
  }

  list(data = paste(data, collapse = "\n"))
}

mcp_client_route_server_message <- function(transport, message, request_id, call = caller_env()) {
  if (mcp_message_is_response(message)) {
    return(mcp_validate_jsonrpc_response(message, request_id, call = call))
  }

  if (is.null(message$method)) {
    return(NULL)
  }

  if (is.null(message$id)) {
    return(NULL)
  }

  response <- mcp_client_handle_server_request(message)
  mcp_transport_http_send(transport, response, expect_response = FALSE, call = call)
  NULL
}

mcp_validate_jsonrpc_response <- function(message, request_id, call = caller_env()) {
  if (!mcp_message_is_response(message)) {
    cli::cli_abort(
      "MCP server returned a JSON-RPC message that was not a response.",
      call = call
    )
  }

  if (!mcp_jsonrpc_id_equal(message$id, request_id)) {
    cli::cli_abort(
      c(
        "MCP server returned a response for an unexpected request id.",
        i = "Expected {.val {request_id}} but received {.val {message$id}}."
      ),
      call = call
    )
  }

  message
}

mcp_jsonrpc_id_equal <- function(x, y) {
  if (is.numeric(x) && is.numeric(y)) {
    return(identical(as.numeric(x), as.numeric(y)))
  }

  identical(x, y)
}

mcp_message_is_response <- function(message) {
  !is.null(message$id) && (!is.null(message$result) || !is.null(message$error))
}

mcp_client_handle_server_request <- function(message) {
  if (identical(message$method, "ping")) {
    return(jsonrpc_response(message$id, result = named_list()))
  }

  jsonrpc_response(
    message$id,
    error = list(code = -32601, message = "Method not found")
  )
}
