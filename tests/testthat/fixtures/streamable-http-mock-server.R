args <- commandArgs(TRUE)
port <- as.integer(args[[1]])
log_file <- args[[2]]
config <- jsonlite::read_json(args[[3]], simplifyVector = FALSE)

empty_object <- function() structure(list(), names = character())

json <- function(x) jsonlite::toJSON(x, auto_unbox = TRUE, null = 'null')

header <- function(req, name) {
  key <- paste0('HTTP_', toupper(gsub('-', '_', name)))
  req[[key]]
}

http_response <- function(status, body = '', headers = list()) {
  headers[['Content-Type']] <- headers[['Content-Type']] %||% 'text/plain'
  headers[['Connection']] <- headers[['Connection']] %||% 'close'
  list(status = status, headers = headers, body = body)
}

accepted_response <- function() {
  http_response(
    202L,
    '',
    list('Content-Type' = 'application/json', 'Content-Length' = '0')
  )
}

json_response <- function(status, body, headers = list()) {
  headers[['Content-Type']] <- 'application/json'
  http_response(status, json(body), headers)
}

sse_response <- function(events) {
  body <- paste(
    vapply(
      seq_along(events),
      function(i) {
        event <- events[[i]]
        id <- event$id %||% paste0('event-', i)
        paste0('id: ', id, '\n', 'data: ', json(event$data), '\n\n')
      },
      character(1)
    ),
    collapse = ''
  )
  http_response(200L, body, list('Content-Type' = 'text/event-stream'))
}

'%||%' <- function(x, y) if (is.null(x)) y else x

read_body <- function(req) {
  body_raw <- req$rook.input$read()
  if (!length(body_raw)) {
    return(NULL)
  }
  body_text <- rawToChar(body_raw)
  tryCatch(
    jsonlite::parse_json(body_text, simplifyVector = FALSE),
    error = function(err) NULL
  )
}

request_entry <- function(req, body) {
  list(
    method = req$REQUEST_METHOD,
    path = req$PATH_INFO,
    headers = list(
      accept = header(req, 'Accept'),
      session_id = header(req, 'MCP-Session-Id'),
      protocol_version = header(req, 'MCP-Protocol-Version'),
      authorization = header(req, 'Authorization'),
      last_event_id = header(req, 'Last-Event-ID')
    ),
    body = body
  )
}

log_request <- function(req, body) {
  cat(json(request_entry(req, body)), '\n', file = log_file, append = TRUE)
}

server_url <- function(req) paste0('http://', req$HTTP_HOST, '/mcp')

metadata_url <- function(req) {
  paste0('http://', req$HTTP_HOST, '/.well-known/oauth-protected-resource/mcp')
}

oauth_challenge <- function(req) {
  http_response(
    401L,
    '',
    list(
      'WWW-Authenticate' = paste0(
        'Bearer resource_metadata="',
        metadata_url(req),
        '"'
      )
    )
  )
}

authorized <- function(req) {
  !isTRUE(config$require_bearer) ||
    identical(
      header(req, 'Authorization'),
      paste('Bearer', config$bearer_token)
    )
}

valid_session <- function(req) {
  identical(header(req, 'MCP-Session-Id'), config$session_id)
}

valid_protocol <- function(req) {
  identical(header(req, 'MCP-Protocol-Version'), config$protocol_version)
}

initialize_result <- function(id) {
  list(
    jsonrpc = '2.0',
    id = id,
    result = list(
      protocolVersion = config$protocol_version,
      capabilities = list(tools = empty_object()),
      serverInfo = list(name = 'mock-streamable-http', version = '1.0.0')
    )
  )
}

tools_list_result <- function(id) {
  list(
    jsonrpc = '2.0',
    id = id,
    result = list(
      tools = list(list(
        name = 'echo',
        description = 'Echo text.',
        inputSchema = list(
          type = 'object',
          properties = list(
            text = list(type = 'string', description = 'Text to echo.')
          ),
          required = list('text')
        )
      ))
    )
  )
}

tool_result <- function(id, text) {
  list(
    jsonrpc = '2.0',
    id = id,
    result = list(
      content = list(list(type = 'text', text = paste('echo:', text))),
      isError = FALSE
    )
  )
}

post_sse_result <- function(message) {
  text <- message$params$arguments$text %||% ''
  events <- list(
    list(
      id = 'post-1',
      data = list(
        jsonrpc = '2.0',
        method = 'notifications/progress',
        params = list(progressToken = 'mock-progress', progress = 0.5)
      )
    ),
    list(id = 'post-2', data = tool_result(message$id, text))
  )
  sse_response(events)
}

handle_post <- function(req) {
  body <- read_body(req)
  log_request(req, body)
  if (is.null(body)) {
    return(json_response(400L, list(error = 'Invalid JSON')))
  }
  if (identical(body$method, 'initialize')) {
    return(json_response(
      200L,
      initialize_result(body$id),
      list('MCP-Session-Id' = config$session_id)
    ))
  }
  if (!valid_session(req)) {
    return(json_response(400L, list(error = 'Invalid MCP-Session-Id')))
  }
  if (!valid_protocol(req)) {
    return(json_response(400L, list(error = 'Invalid MCP-Protocol-Version')))
  }
  if (is.null(body$id)) {
    return(accepted_response())
  }
  if (identical(body$method, 'tools/list')) {
    return(json_response(200L, tools_list_result(body$id)))
  }
  if (identical(body$method, 'tools/call')) {
    if (isTRUE(config$post_sse)) {
      return(post_sse_result(body))
    }
    text <- body$params$arguments$text %||% ''
    return(json_response(200L, tool_result(body$id, text)))
  }
  json_response(
    200L,
    list(jsonrpc = '2.0', id = body$id, result = empty_object())
  )
}

handle_get <- function(req) {
  if (identical(req$PATH_INFO, '/health')) {
    return(http_response(204L))
  }
  if (identical(req$PATH_INFO, '/.well-known/oauth-protected-resource/mcp')) {
    return(json_response(
      200L,
      list(
        resource = server_url(req),
        authorization_servers = list(paste0('http://', req$HTTP_HOST, '/auth'))
      )
    ))
  }
  http_response(405L, 'Method Not Allowed', list(Allow = 'POST, DELETE'))
}

handle_delete <- function(req) {
  log_request(req, NULL)
  if (!valid_session(req)) {
    return(json_response(400L, list(error = 'Invalid MCP-Session-Id')))
  }
  http_response(204L)
}

app <- list(call = function(req) {
  tryCatch(
    {
      if (
        !identical(req$PATH_INFO, '/health') &&
          !identical(
            req$PATH_INFO,
            '/.well-known/oauth-protected-resource/mcp'
          ) &&
          !authorized(req)
      ) {
        return(oauth_challenge(req))
      }
      switch(
        req$REQUEST_METHOD,
        POST = handle_post(req),
        GET = handle_get(req),
        DELETE = handle_delete(req),
        http_response(
          405L,
          'Method Not Allowed',
          list(Allow = 'GET, POST, DELETE')
        )
      )
    },
    error = function(err) {
      json_response(500L, list(error = conditionMessage(err)))
    }
  )
})

server <- httpuv::startServer('127.0.0.1', port, app)
on.exit(httpuv::stopServer(server), add = TRUE)
httpuv::service(Inf)
