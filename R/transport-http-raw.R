raw_http_max_request_bytes <- 10L * 1024L * 1024L

mcp_server_http_raw <- function(host, port) {
  server <- raw_http_server_state(host)
  listener <- serverSocket(port)
  on.exit(raw_http_close_server(server, listener), add = TRUE)

  the$raw_http_server <- server
  on.exit(the$raw_http_server <- NULL, add = TRUE)

  cat(sprintf("MCP server listening on http://%s:%d\n", host, port))

  repeat {
    raw_http_service_once(server, listener)
  }
}

raw_http_server_state <- function(host) {
  server <- new.env(parent = emptyenv())
  server$host <- host
  server$connections <- list()
  server$sessions <- new.env(hash = TRUE, parent = emptyenv())
  server$pending <- new.env(hash = TRUE, parent = emptyenv())
  server$subscriptions <- list()
  server$jobs <- list()
  server$next_server_request_id <- 1L
  server
}

raw_http_service_once <- function(server, listener) {
  raw_http_run_jobs(server)
  active <- Filter(
    function(connection) !isTRUE(connection$closed),
    server$connections
  )
  server$connections <- active
  server$subscriptions <- Filter(
    function(connection) !isTRUE(connection$closed),
    server$subscriptions
  )

  sockets <- c(list(listener), lapply(active, function(connection) {
    connection$con
  }))
  ready <- socketSelect(
    sockets,
    timeout = raw_http_select_timeout(server)
  )

  if (isTRUE(ready[[1]])) {
    raw_http_accept_connection(server, listener)
  }

  if (length(active)) {
    for (i in seq_along(active)) {
      if (isTRUE(ready[[i + 1L]])) {
        raw_http_read_connection(server, active[[i]])
      }
    }
  }

  raw_http_run_jobs(server)
  invisible()
}

raw_http_select_timeout <- function(server) {
  if (!length(server$jobs)) {
    return(0.05)
  }

  due <- vapply(server$jobs, function(job) job$at, numeric(1))
  max(0, min(0.05, min(due) - raw_http_now()))
}

raw_http_accept_connection <- function(server, listener) {
  con <- socketAccept(
    listener,
    blocking = FALSE,
    open = "a+b",
    options = "no-delay"
  )

  if (!raw_http_peer_allowed(con, server$host)) {
    logcat(paste(
      "Rejected non-loopback peer on loopback HTTP listener:",
      summary(con)$description
    ))
    close(con)
    return(invisible())
  }

  connection <- new.env(parent = emptyenv())
  connection$con <- con
  connection$buffer <- raw()
  connection$closed <- FALSE
  connection$handled <- FALSE
  connection$mode <- "request"
  connection$session <- NULL
  connection$last_event_id <- NULL
  connection$replay <- FALSE
  server$connections[[length(server$connections) + 1L]] <- connection
  invisible()
}

raw_http_peer_allowed <- function(con, host) {
  if (!host %in% c("127.0.0.1", "localhost", "::1", "[::1]")) {
    return(TRUE)
  }

  description <- summary(con)$description %||% ""
  grepl("^<-(localhost|127\\.)", description)
}

raw_http_read_connection <- function(server, connection) {
  incoming <- tryCatch(
    readBin(connection$con, "raw", n = 65536L),
    error = function(err) {
      logcat(paste("HTTP socket read failed:", conditionMessage(err)))
      raw()
    }
  )

  if (!length(incoming)) {
    raw_http_close_connection(connection)
    return(invisible())
  }

  if (isTRUE(connection$handled)) {
    return(invisible())
  }

  connection$buffer <- c(connection$buffer, incoming)
  if (length(connection$buffer) > raw_http_max_request_bytes) {
    raw_http_send_response(
      connection,
      list(
        status = 413L,
        headers = list("Content-Type" = "text/plain"),
        body = "Request Entity Too Large"
      )
    )
    return(invisible())
  }

  parsed <- raw_http_parse_request(connection$buffer)
  if (is.null(parsed)) {
    return(invisible())
  }
  if (inherits(parsed, "raw_http_parse_error")) {
    raw_http_send_response(connection, http_bad_request(parsed$message))
    return(invisible())
  }

  connection$handled <- TRUE
  raw_http_dispatch_request(server, connection, parsed)
}

raw_http_parse_request <- function(buffer) {
  header_start <- raw_http_find_bytes(buffer, charToRaw("\r\n\r\n"))
  if (is.null(header_start)) {
    return(NULL)
  }

  header_raw <- if (header_start == 1L) {
    raw()
  } else {
    buffer[seq_len(header_start - 1L)]
  }
  header_text <- tryCatch(
    rawToChar(header_raw),
    error = function(err) NULL
  )
  if (is.null(header_text)) {
    return(raw_http_parse_error("Invalid HTTP header encoding"))
  }

  lines <- strsplit(header_text, "\r\n", fixed = TRUE)[[1]]
  request_line <- strsplit(lines[[1]], " ", fixed = TRUE)[[1]]
  if (length(request_line) != 3L) {
    return(raw_http_parse_error("Invalid HTTP request line"))
  }

  headers <- list()
  if (length(lines) > 1L) {
    for (line in lines[-1L]) {
      separator <- regexpr(":", line, fixed = TRUE)[[1]]
      if (separator < 2L) {
        return(raw_http_parse_error("Invalid HTTP header"))
      }
      name <- tolower(trimws(substr(line, 1L, separator - 1L)))
      value <- trimws(substr(line, separator + 1L, nchar(line)))
      if (is.null(headers[[name]])) {
        headers[[name]] <- value
      } else {
        headers[[name]] <- paste(headers[[name]], value, sep = ", ")
      }
    }
  }

  if (!is.null(headers[["transfer-encoding"]])) {
    return(raw_http_parse_error(
      "Chunked request bodies are not supported"
    ))
  }

  content_length <- headers[["content-length"]] %||% "0"
  if (!grepl("^[0-9]+$", content_length)) {
    return(raw_http_parse_error("Invalid Content-Length"))
  }
  content_length <- suppressWarnings(as.numeric(content_length))
  if (
    !is.finite(content_length) ||
      content_length < 0 ||
      content_length > raw_http_max_request_bytes
  ) {
    return(raw_http_parse_error("Invalid Content-Length"))
  }

  body_start <- header_start + 4L
  available <- length(buffer) - body_start + 1L
  if (available < content_length) {
    return(NULL)
  }

  body_raw <- if (content_length == 0L) {
    raw()
  } else {
    buffer[body_start:(body_start + content_length - 1L)]
  }
  body <- tryCatch(
    rawToChar(body_raw),
    error = function(err) NULL
  )
  if (is.null(body)) {
    return(raw_http_parse_error("Invalid HTTP request body"))
  }

  list(
    method = request_line[[1]],
    target = request_line[[2]],
    version = request_line[[3]],
    headers = headers,
    body = body
  )
}

raw_http_find_bytes <- function(buffer, needle) {
  n_buffer <- length(buffer)
  n_needle <- length(needle)
  if (!n_needle || n_buffer < n_needle) {
    return(NULL)
  }

  starts <- which(
    buffer[seq_len(n_buffer - n_needle + 1L)] == needle[[1]]
  )
  for (start in starts) {
    indices <- start + seq_len(n_needle) - 1L
    if (identical(buffer[indices], needle)) {
      return(start)
    }
  }
  NULL
}

raw_http_parse_error <- function(message) {
  structure(list(message = message), class = "raw_http_parse_error")
}

raw_http_dispatch_request <- function(server, connection, request) {
  req <- raw_http_rook_request(request)
  validation_error <- http_request_validation_error(req)
  if (!is.null(validation_error)) {
    raw_http_send_response(connection, validation_error)
    return(invisible())
  }

  if (identical(request$method, "GET")) {
    session <- raw_http_require_session(server, connection, request)
    if (!is.null(session)) {
      raw_http_open_get_stream(server, connection, request, session)
    }
    return(invisible())
  }

  if (identical(request$method, "DELETE")) {
    session <- raw_http_require_session(server, connection, request)
    if (!is.null(session)) {
      raw_http_delete_session(server, session)
      raw_http_send_response(
        connection,
        list(
          status = 200L,
          headers = list("Content-Type" = "application/json"),
          body = "{}"
        )
      )
    }
    return(invisible())
  }

  if (!identical(request$method, "POST")) {
    raw_http_send_response(connection, handle_http_request(req))
    return(invisible())
  }

  data <- tryCatch(
    jsonlite::parse_json(request$body),
    error = function(err) NULL
  )
  if (is.null(data)) {
    raw_http_send_response(connection, handle_http_request(req))
    return(invisible())
  }

  if (is_stateless_http_request(req, data)) {
    raw_http_dispatch_stateless_request(server, connection, req, data)
    return(invisible())
  }

  if (identical(data$method, "initialize")) {
    response <- handle_http_request(req)
    raw_http_register_session(server, data, response)
    raw_http_send_response(connection, response)
    return(invisible())
  }

  session <- raw_http_require_session(
    server,
    connection,
    request,
    data$id
  )
  if (is.null(session)) {
    return(invisible())
  }

  if (is.null(data$method)) {
    raw_http_handle_jsonrpc_response(
      server,
      connection,
      session,
      data
    )
    return(invisible())
  }

  if (raw_http_is_server_request_tool(data, req)) {
    raw_http_start_server_request_tool(
      server,
      connection,
      session,
      data
    )
    return(invisible())
  }

  if (
    identical(data$method, "tools/call") &&
      identical(data$params$name, "test_reconnection") &&
      http_accepts_event_stream(req)
  ) {
    raw_http_start_reconnection(
      server,
      connection,
      session,
      data
    )
    return(invisible())
  }

  raw_http_send_response(connection, handle_http_request(req))
  invisible()
}

raw_http_dispatch_stateless_request <- function(
  server,
  connection,
  req,
  data
) {
  if (identical(data$method, "subscriptions/listen")) {
    validation_error <- stateless_request_validation_error(req, data)
    if (!is.null(validation_error)) {
      raw_http_send_response(connection, validation_error)
      return(invisible())
    }
    raw_http_open_subscription_stream(server, connection, data)
    return(invisible())
  }

  response <- handle_http_request(req)
  raw_http_send_response(connection, response)

  if (
    identical(data$method, "tools/call") &&
      response$status == 200L
  ) {
    if (identical(data$params$name, "test_trigger_tool_change")) {
      raw_http_notify_subscriptions(server, "tools")
    } else if (identical(data$params$name, "test_trigger_prompt_change")) {
      raw_http_notify_subscriptions(server, "prompts")
    }
  }
  invisible()
}

raw_http_open_subscription_stream <- function(server, connection, data) {
  raw_http_begin_ndjson(connection)
  connection$mode <- "ndjson-subscription"
  connection$subscription_id <- as.character(data$id)
  connection$subscription_notifications <-
    data$params$notifications %||% named_list()
  server$subscriptions[[length(server$subscriptions) + 1L]] <- connection

  raw_http_write_ndjson(
    connection,
    list(
      jsonrpc = "2.0",
      method = "notifications/subscriptions/acknowledged",
      params = list(
        `_meta` = list(
          `io.modelcontextprotocol/subscriptionId` =
            connection$subscription_id
        ),
        notifications = connection$subscription_notifications
      )
    )
  )
  invisible()
}

raw_http_notify_subscriptions <- function(server, type) {
  server$subscriptions <- Filter(
    function(connection) !isTRUE(connection$closed),
    server$subscriptions
  )

  filter_name <- switch(
    type,
    tools = "toolsListChanged",
    prompts = "promptsListChanged"
  )
  method <- paste0("notifications/", type, "/list_changed")
  for (connection in server$subscriptions) {
    if (!isTRUE(connection$subscription_notifications[[filter_name]])) {
      next
    }
    raw_http_write_ndjson(
      connection,
      list(
        jsonrpc = "2.0",
        method = method,
        params = list(
          `_meta` = list(
            `io.modelcontextprotocol/subscriptionId` =
              connection$subscription_id
          )
        )
      )
    )
  }
  invisible()
}

raw_http_rook_request <- function(request) {
  req <- list(
    REQUEST_METHOD = request$method,
    PATH_INFO = sub("\\?.*$", "", request$target),
    QUERY_STRING = if (grepl("?", request$target, fixed = TRUE)) {
      sub("^[^?]*\\?", "", request$target)
    } else {
      ""
    }
  )

  for (name in names(request$headers)) {
    rook_name <- toupper(gsub("-", "_", name, fixed = TRUE))
    req[[paste0("HTTP_", rook_name)]] <- request$headers[[name]]
    if (rook_name %in% c("CONTENT_LENGTH", "CONTENT_TYPE")) {
      req[[rook_name]] <- request$headers[[name]]
    }
  }

  body <- charToRaw(request$body)
  req$rook.input <- local({
    payload <- body
    list(read = function(...) payload)
  })
  req
}

raw_http_require_session <- function(
  server,
  connection,
  request,
  id = NULL
) {
  session_id <- request$headers[["mcp-session-id"]]
  if (!is_string(session_id) || !nzchar(session_id)) {
    raw_http_send_session_error(
      connection,
      400L,
      -32000L,
      "Invalid or missing session ID",
      id
    )
    return(NULL)
  }

  session <- server$sessions[[session_id]]
  if (is.null(session)) {
    raw_http_send_session_error(
      connection,
      404L,
      -32001L,
      "Session not found",
      id
    )
    return(NULL)
  }

  session
}

raw_http_send_session_error <- function(
  connection,
  status,
  code,
  message,
  id
) {
  error <- list(code = code, message = message)
  body <- if (is.null(id)) {
    to_json(error)
  } else {
    to_json(jsonrpc_response(id, error = error))
  }
  raw_http_send_response(
    connection,
    list(
      status = status,
      headers = list("Content-Type" = "application/json"),
      body = body
    )
  )
}

raw_http_register_session <- function(server, data, response) {
  session_id <- response$headers[["MCP-Session-Id"]]
  if (!is_string(session_id)) {
    return(invisible())
  }

  session <- new.env(parent = emptyenv())
  session$id <- session_id
  session$protocol_version <- data$params$protocolVersion
  session$client_capabilities <- data$params$capabilities %||% named_list()
  session$events <- list()
  session$streams <- list()
  session$next_event_id <- 1L
  server$sessions[[session_id]] <- session
  invisible()
}

raw_http_delete_session <- function(server, session) {
  for (stream in session$streams) {
    raw_http_close_connection(stream)
  }

  pending_ids <- ls(server$pending, all.names = TRUE)
  for (id in pending_ids) {
    pending <- server$pending[[id]]
    if (identical(pending$session_id, session$id)) {
      raw_http_close_connection(pending$connection)
      rm(list = id, envir = server$pending)
    }
  }

  rm(list = session$id, envir = server$sessions)
  invisible()
}

raw_http_is_server_request_tool <- function(data, req) {
  if (
    !identical(data$method, "tools/call") ||
      !http_accepts_event_stream(req)
  ) {
    return(FALSE)
  }

  tool_name <- data$params$name
  is_string(tool_name) &&
    tool_name %in% c(
      "test_sampling",
      "test_elicitation",
      "test_elicitation_sep1034_defaults",
      "test_elicitation_sep1330_enums"
    ) &&
    tool_name %in% names(get_mcptools_tools())
}

raw_http_start_server_request_tool <- function(
  server,
  connection,
  session,
  data
) {
  raw_http_begin_sse(connection)
  raw_http_write_event(
    connection,
    raw_http_store_event(session, "", retry = 5000L)
  )

  server_request_id <- paste0(
    "server-",
    server$next_server_request_id
  )
  server$next_server_request_id <- server$next_server_request_id + 1L
  tool_name <- data$params$name
  server_request <- if (identical(tool_name, "test_sampling")) {
    mcp_sampling_request(data, server_request_id)
  } else {
    mcp_elicitation_request(data, server_request_id)
  }

  pending <- list(
    id = server_request_id,
    session_id = session$id,
    connection = connection,
    tool_request_id = data$id,
    tool_name = tool_name
  )
  server$pending[[raw_http_id_key(server_request_id)]] <- pending
  raw_http_write_event(
    connection,
    raw_http_store_event(session, server_request)
  )
  invisible()
}

raw_http_handle_jsonrpc_response <- function(
  server,
  connection,
  session,
  data
) {
  key <- raw_http_id_key(data$id)
  pending <- server$pending[[key]]
  raw_http_send_response(
    connection,
    list(
      status = 202L,
      headers = list("Content-Type" = "application/json"),
      body = ""
    )
  )

  if (
    is.null(pending) ||
      !identical(pending$session_id, session$id)
  ) {
    return(invisible())
  }

  response <- if (identical(pending$tool_name, "test_sampling")) {
    mcp_sampling_tool_response(data, pending$tool_request_id)
  } else {
    mcp_elicitation_tool_response(
      data,
      pending$tool_request_id,
      pending$tool_name
    )
  }
  event <- raw_http_store_event(session, response, terminal = TRUE)

  if (!isTRUE(pending$connection$closed)) {
    raw_http_write_event(pending$connection, event)
    raw_http_close_connection(pending$connection)
  } else {
    raw_http_deliver_to_replay_streams(session, event)
  }

  rm(list = key, envir = server$pending)
  invisible()
}

raw_http_id_key <- function(id) {
  paste0(typeof(id), ":", paste(id, collapse = ","))
}

raw_http_start_reconnection <- function(
  server,
  connection,
  session,
  data
) {
  raw_http_begin_sse(connection)
  raw_http_write_event(
    connection,
    raw_http_store_event(session, "", retry = 5000L)
  )
  raw_http_schedule(server, 0.1, function() {
    raw_http_complete_reconnection(
      server,
      session$id,
      data$id
    )
  })
  raw_http_close_connection(connection)
  invisible()
}

raw_http_complete_reconnection <- function(
  server,
  session_id,
  request_id
) {
  session <- server$sessions[[session_id]]
  if (is.null(session)) {
    return(invisible())
  }

  response <- jsonrpc_response(
    request_id,
    result = list(content = list(list(
      type = "text",
      text = paste(
        "Reconnection test completed successfully.",
        "The SSE stream was resumed with event replay."
      )
    )))
  )
  event <- raw_http_store_event(session, response, terminal = TRUE)
  raw_http_deliver_to_replay_streams(session, event)
  invisible()
}

raw_http_open_get_stream <- function(
  server,
  connection,
  request,
  session
) {
  raw_http_begin_sse(connection)
  connection$mode <- "sse-get"
  connection$session <- session
  connection$replay <- !is.null(request$headers[["last-event-id"]])
  connection$last_event_id <- request$headers[["last-event-id"]]
  session$streams[[length(session$streams) + 1L]] <- connection

  if (isTRUE(connection$replay)) {
    events <- raw_http_events_after(
      session,
      connection$last_event_id
    )
    for (event in events) {
      raw_http_write_event(connection, event)
      connection$last_event_id <- event$id
    }
    if (length(events) && isTRUE(events[[length(events)]]$terminal)) {
      raw_http_close_connection(connection)
    }
  } else {
    priming <- raw_http_store_event(session, "", retry = 5000L)
    raw_http_write_event(connection, priming)
    connection$last_event_id <- priming$id
  }

  invisible()
}

raw_http_events_after <- function(session, last_event_id) {
  if (!length(session$events)) {
    return(list())
  }

  ids <- vapply(session$events, function(event) event$id, character(1))
  position <- match(last_event_id, ids)
  if (is.na(position)) {
    return(session$events)
  }
  if (position == length(session$events)) {
    return(list())
  }

  session$events[(position + 1L):length(session$events)]
}

raw_http_deliver_to_replay_streams <- function(session, event) {
  session$streams <- Filter(
    function(stream) !isTRUE(stream$closed),
    session$streams
  )
  for (stream in session$streams) {
    if (
      isTRUE(stream$replay) &&
        !identical(stream$last_event_id, event$id)
    ) {
      raw_http_write_event(stream, event)
      stream$last_event_id <- event$id
      if (isTRUE(event$terminal)) {
        raw_http_close_connection(stream)
      }
    }
  }
  invisible()
}

raw_http_store_event <- function(
  session,
  data,
  event = "message",
  retry = NULL,
  terminal = FALSE
) {
  id <- paste0(session$id, "-", session$next_event_id)
  session$next_event_id <- session$next_event_id + 1L
  data <- if (is.character(data)) {
    paste(data, collapse = "")
  } else {
    as.character(to_json(data))
  }

  stored <- list(
    id = id,
    event = event,
    data = data,
    retry = retry,
    terminal = terminal,
    frame = sse_event(
      data = data,
      id = id,
      event = event,
      retry = retry
    )
  )
  session$events[[length(session$events) + 1L]] <- stored
  if (length(session$events) > 1000L) {
    session$events <- tail(session$events, 1000L)
  }
  stored
}

raw_http_schedule <- function(server, delay, callback) {
  server$jobs[[length(server$jobs) + 1L]] <- list(
    at = raw_http_now() + delay,
    callback = callback
  )
  invisible()
}

raw_http_run_jobs <- function(server) {
  if (!length(server$jobs)) {
    return(invisible())
  }

  now <- raw_http_now()
  due <- vapply(server$jobs, function(job) job$at <= now, logical(1))
  jobs <- server$jobs[due]
  server$jobs <- server$jobs[!due]
  for (job in jobs) {
    tryCatch(
      job$callback(),
      error = function(err) {
        logcat(paste("Scheduled HTTP transport job failed:", conditionMessage(err)))
      }
    )
  }
  invisible()
}

raw_http_now <- function() {
  as.numeric(Sys.time())
}

raw_http_begin_sse <- function(connection) {
  raw_http_write(
    connection,
    paste0(
      "HTTP/1.1 200 OK\r\n",
      "Content-Type: text/event-stream\r\n",
      "Cache-Control: no-cache\r\n",
      "Connection: close\r\n",
      "X-Accel-Buffering: no\r\n\r\n"
    )
  )
  connection$mode <- "sse"
  invisible()
}

raw_http_begin_ndjson <- function(connection) {
  raw_http_write(
    connection,
    paste0(
      "HTTP/1.1 200 OK\r\n",
      "Content-Type: application/x-ndjson\r\n",
      "Cache-Control: no-cache\r\n",
      "Transfer-Encoding: chunked\r\n",
      "Connection: close\r\n",
      "X-Accel-Buffering: no\r\n\r\n"
    )
  )
  connection$mode <- "ndjson"
  invisible()
}

raw_http_write_ndjson <- function(connection, message) {
  raw_http_write_chunk(connection, paste0(to_json(message), "\n"))
}

raw_http_write_chunk <- function(connection, text) {
  encoded <- enc2utf8(text)
  raw_http_write(
    connection,
    paste0(
      sprintf("%x", length(charToRaw(encoded))),
      "\r\n",
      encoded,
      "\r\n"
    )
  )
}

raw_http_write_event <- function(connection, event) {
  raw_http_write(connection, event$frame)
}

raw_http_send_response <- function(connection, response) {
  body <- response$body %||% ""
  body <- enc2utf8(paste(body, collapse = ""))
  headers <- response$headers %||% list()
  header_names <- tolower(names(headers) %||% character())

  if (!"content-length" %in% header_names) {
    headers[["Content-Length"]] <- length(charToRaw(body))
  }
  if (!"connection" %in% header_names) {
    headers[["Connection"]] <- "close"
  }

  header_text <- paste(
    vapply(
      names(headers),
      function(name) paste0(name, ": ", headers[[name]]),
      character(1)
    ),
    collapse = "\r\n"
  )
  raw_http_write(
    connection,
    paste0(
      "HTTP/1.1 ",
      response$status,
      " ",
      raw_http_status_text(response$status),
      "\r\n",
      header_text,
      "\r\n\r\n",
      body
    )
  )
  raw_http_close_connection(connection)
  invisible()
}

raw_http_status_text <- function(status) {
  switch(
    as.character(status),
    `200` = "OK",
    `202` = "Accepted",
    `204` = "No Content",
    `400` = "Bad Request",
    `403` = "Forbidden",
    `404` = "Not Found",
    `405` = "Method Not Allowed",
    `413` = "Content Too Large",
    `500` = "Internal Server Error",
    "Response"
  )
}

raw_http_write <- function(connection, text) {
  if (isTRUE(connection$closed)) {
    return(FALSE)
  }

  written <- tryCatch(
    {
      writeBin(charToRaw(enc2utf8(text)), connection$con)
      flush(connection$con)
      TRUE
    },
    error = function(err) {
      logcat(paste("HTTP socket write failed:", conditionMessage(err)))
      FALSE
    }
  )
  if (!written) {
    raw_http_close_connection(connection)
  }
  written
}

raw_http_close_connection <- function(connection) {
  if (isTRUE(connection$closed)) {
    return(invisible())
  }

  tryCatch(
    close(connection$con),
    error = function(err) {
      logcat(paste("HTTP socket close failed:", conditionMessage(err)))
    }
  )
  connection$closed <- TRUE
  invisible()
}

raw_http_close_server <- function(server, listener) {
  for (connection in server$connections) {
    raw_http_close_connection(connection)
  }
  close(listener)
  invisible()
}
