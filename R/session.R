#' @rdname server
#' @export
mcp_session <- function() {
  ensure_socket_dir(socket_dir_in_use())
  socket_secret()

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

handle_message_from_server <- function(wire) {
  pipe <- nanonext::pipe_id(the$raio)
  schedule_handle_message_from_server()

  payload <- mac_open(wire)
  if (is.null(payload)) {
    return(invisible())
  }
  data <- unserialize(payload)

  if (length(data) == 0) {
    return(session_send(session_metadata(), pipe))
  }

  err <- validate_session_message(data)
  if (!is.null(err)) {
    body <- err
  } else if (data$method == "tools/call") {
    body <- execute_tool_call(data)
  } else {
    body <- jsonrpc_response(
      data$id,
      error = list(code = -32601, message = "Method not found")
    )
  }

  session_send(to_json(body), pipe)
}

session_send <- function(text, pipe) {
  nanonext::send_aio(
    the$session_socket,
    mac_seal(charToRaw(as.character(text))),
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
      content = as_mcp_content(
        result,
        structured_content,
        restrict_private = isTRUE(data$restrictFetch)
      ),
      structuredContent = structured_content,
      isError = is_error
    ))
  )
}

as_mcp_content <- function(result, structured_content = NULL, restrict_private = FALSE) {
  if (!is.null(structured_content)) {
    return(list(list(
      type = "text",
      text = as.character(to_json(structured_content))
    )))
  }

  if (inherits(result, "ellmer::ContentToolResult")) {
    value <- result@value
    if (has_mcp_content(value)) {
      return(as_mcp_content(value, restrict_private = restrict_private))
    }

    return(list(as_mcp_text_content(result)))
  }

  if (is_mcp_content(result)) {
    return(list(as_mcp_content_block(result, restrict_private = restrict_private)))
  }

  if (is.list(result) && has_mcp_content(result)) {
    return(unname(unlist(
      lapply(result, as_mcp_content, restrict_private = restrict_private),
      recursive = FALSE
    )))
  }

  list(as_mcp_text_content(result))
}

as_mcp_content_block <- function(result, restrict_private = FALSE) {
  if (is_mcp_content_block_list(result)) {
    return(result)
  }

  if (inherits(result, "ellmer::ContentImageInline")) {
    return(list(type = "image", data = result@data, mimeType = result@type))
  }

  if (inherits(result, "ellmer::ContentImageRemote")) {
    return(remote_image_as_mcp_content_block(result, restrict_private = restrict_private))
  }

  if (inherits(result, "ellmer::ContentText")) {
    return(list(type = "text", text = result@text))
  }

  as_mcp_text_content(result)
}

# MCP image content blocks carry inlined base64 data, but a ContentImageRemote
# holds only a URL. Fetch and encode it server-side so tools returning
# `content_image_url()` transmit an image rather than degrading to text.
remote_image_as_mcp_content_block <- function(result, restrict_private = FALSE, call = caller_env()) {
  url <- result@url
  resp <- fetch_remote_image(url, restrict_private = restrict_private, call = call)

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

# Follow redirects ourselves, validating each hop before requesting it: curl's
# own redirect following would let a public URL bounce the fetch to an internal
# address past validate_remote_image_url(). `restrict_private` is set only for
# network-facing (HTTP) deployments, where a remote client can steer the URL
# through a tool argument; local stdio use fetches its own machine freely.
fetch_remote_image <- function(url, restrict_private = FALSE, call = caller_env()) {
  max_redirects <- 5L

  for (i in seq_len(max_redirects + 1L)) {
    validate_remote_image_url(url, restrict_private = restrict_private, call = call)

    resp <- tryCatch(
      httr2::req_perform(
        mcp_req_no_redirects(httr2::req_timeout(httr2::request(url), 30))
      ),
      error = function(cnd) {
        cli::cli_abort(
          "Failed to fetch remote image content from {.url {url}}.",
          parent = cnd,
          call = call
        )
      }
    )

    if (httr2::resp_status(resp) < 300L) {
      return(resp)
    }

    location <- httr2::resp_header(resp, "location")
    if (is.null(location)) {
      cli::cli_abort(
        c(
          "Failed to fetch remote image content from {.url {url}}.",
          i = "The server responded with a redirect but no {.field Location}."
        ),
        call = call
      )
    }

    url <- httr2::url_modify_relative(url, location)
  }

  cli::cli_abort(
    c(
      "Failed to fetch remote image content.",
      i = "Exceeded the {max_redirects}-redirect limit."
    ),
    call = call
  )
}

# Refuse fetches that could reach the local filesystem (non-http schemes) or, in
# a network-facing deployment, internal services (private/loopback/link-local IP
# literals such as cloud metadata or RFC 1918 hosts). Applied to every redirect
# hop, not just the initial URL.
validate_remote_image_url <- function(url, restrict_private = FALSE, call = caller_env()) {
  parsed <- url_parse_or_null(url)
  scheme <- tolower(parsed$scheme %||% "")
  if (!scheme %in% c("http", "https")) {
    cli::cli_abort(
      c(
        "Remote image content must be fetched over http or https.",
        i = "Refusing to fetch {.url {url}}."
      ),
      call = call
    )
  }

  if (restrict_private && is_private_host_literal(parsed$hostname %||% "")) {
    cli::cli_abort(
      c(
        "Remote image content must not reference a private or loopback address.",
        i = "Refusing to fetch {.url {url}}."
      ),
      call = call
    )
  }

  invisible(url)
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
  is_mcp_content_block_list(result) ||
    inherits(result, "ellmer::ContentImageInline") ||
    inherits(result, "ellmer::ContentImageRemote") ||
    inherits(result, "ellmer::ContentText")
}

is_mcp_content_block_list <- function(result) {
  is.list(result) &&
    is_string(result$type) &&
    result$type %in% c("text", "image", "audio", "resource")
}

schedule_handle_message_from_server <- function() {
  the$raio <- nanonext::recv_aio(the$session_socket, mode = "raw")
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
