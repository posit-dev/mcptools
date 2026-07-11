#' @rdname server
#' @export
mcp_session <- function() {
  ensure_socket_dir(socket_dir_in_use())

  the$session_socket <- nanonext::socket("poly")
  i <- 1L
  while (i < 1024L) {
    # prevent indefinite loop
    url <- sprintf("%s%d", the$socket_url, i)
    if (!nanonext::is_error_value(
      nanonext::listen(the$session_socket, url = url, fail = "none")
    )) {
      break
    }
    if (
      reclaim_stale_socket(url) &&
        !nanonext::is_error_value(
          nanonext::listen(the$session_socket, url = url, fail = "none")
        )
    ) {
      break
    }
    i <- i + 1L
  }
  the$session <- i

  # Register once for exit cleanup -- filesystem sockets persist, unlike
  # abstract sockets which the kernel cleans automatically. Guard against
  # repeat mcp_session() calls stacking duplicate finalizers on `the`.
  if (!isTRUE(the$finalizer_registered)) {
    reg.finalizer(the, function(e) cleanup_session_socket(), onexit = TRUE)
    the$finalizer_registered <- TRUE
  }

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
        session_metadata(),
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

  structured_content <- as_mcp_structured_content(
    result,
    data$protocolVersion %||% the$protocol_version %||% latest_protocol_version
  )

  jsonrpc_response(
    data$id,
    drop_nulls(list(
      content = as_mcp_content(result, structured_content),
      structuredContent = structured_content,
      isError = is_error
    ))
  )
}

as_mcp_content <- function(result, structured_content = NULL) {
  if (!is.null(structured_content)) {
    return(list(list(
      type = "text",
      text = as.character(to_json(structured_content))
    )))
  }

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

  if (inherits(result, "ellmer::ContentImageRemote")) {
    return(remote_image_as_mcp_content_block(result))
  }

  if (inherits(result, "ellmer::ContentText")) {
    return(list(type = "text", text = result@text))
  }

  as_mcp_text_content(result)
}

# MCP image content blocks carry inlined base64 data, but a ContentImageRemote
# holds only a URL. Fetch and encode it server-side so tools returning
# `content_image_url()` transmit an image rather than degrading to text.
remote_image_as_mcp_content_block <- function(result, call = caller_env()) {
  url <- result@url

  resp <- tryCatch(
    httr2::req_perform(httr2::req_timeout(httr2::request(url), 30)),
    error = function(cnd) {
      cli::cli_abort(
        "Failed to fetch remote image content from {.url {url}}.",
        parent = cnd,
        call = call
      )
    }
  )

  body <- httr2::resp_body_raw(resp)
  max_bytes <- 10L * 1024L^2
  if (length(body) > max_bytes) {
    cli::cli_abort(
      c(
        "Remote image content from {.url {url}} is too large to inline.",
        i = "mcptools inlines remote images up to {max_bytes} bytes."
      ),
      call = call
    )
  }

  list(
    type = "image",
    data = gsub("\n", "", jsonlite::base64_enc(body), fixed = TRUE),
    mimeType = httr2::resp_content_type(resp) %||% "image/png"
  )
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

as_mcp_structured_content <- function(result, protocol_version) {
  if (protocol_version_lt(protocol_version, "2025-06-18")) {
    return(NULL)
  }

  result <- unwrap_tool_result_value(result)
  if (is.null(result) || has_mcp_content(result)) {
    return(NULL)
  }

  if (!is_structured_content_result(result)) {
    return(NULL)
  }

  jsonlite::parse_json(to_json(as_json_object_result(result)))
}

unwrap_tool_result_value <- function(result) {
  if (!inherits(result, "ellmer::ContentToolResult")) {
    return(result)
  }

  if (!is.null(result@error)) {
    return(NULL)
  }

  result@value
}

is_structured_content_result <- function(result) {
  if (inherits(result, "ellmer::Content")) {
    return(FALSE)
  }

  if (is.data.frame(result) || is.matrix(result) || is.array(result)) {
    return(FALSE)
  }

  result_names <- names(result)
  if (is.null(result_names)) {
    return(FALSE)
  }

  length(result_names) == length(result) && all(nzchar(result_names))
}

as_json_object_result <- function(result) {
  if (is.atomic(result)) {
    return(as.list(result))
  }

  result
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
    inherits(result, "ellmer::ContentImageRemote") ||
    inherits(result, "ellmer::ContentText")
}

schedule_handle_message_from_server <- function() {
  the$raio <- nanonext::recv_aio(the$session_socket, mode = "serial")
  promises::as.promise(the$raio)$then(handle_message_from_server)$catch(
    log_session_error
  )
}

log_session_error <- function(e) {
  msg <- paste("[mcptools] session error:", conditionMessage(e))
  message(msg)
  logcat(msg)
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

# Structured reply to a discovery probe: `wd` lets the server match a session
# to its own working directory when auto-connecting (see
# ensure_session_connection()). Older servers show this JSON string verbatim
# in list_r_sessions() output; newer ones extract `description`.
session_metadata <- function() {
  as.character(to_json(list(
    session = the$session,
    wd = getwd(),
    description = describe_session()
  )))
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
