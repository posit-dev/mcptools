library(httpuv)
library(jsonlite)

# stopAllServers()
s <- startServer(
  host = "127.0.0.1",
  port = 8000,
  app = list(
    call = function(req) {
      serve(req)
    }
  )
)



serve <- function(req) {
  req_body <- rawToChar(req$rook.input$read())

  # In RStudio, content logged to stderr will show in red.
  # cat(req_body, file=stderr())
  data <- fromJSON(req_body)
  # cat(paste(capture.output(str(data)), collapse="\n"), file=stderr())


  if (data$method == "tools/call") {
    name <- data$params$name
    fn <- getNamespace("btw")[[name]]
    args <- data$params$arguments

    # HACK for btw_tool_env_describe_environment. In the JSON, it will have
    # `"items": []`, and that translates to an empty list, but we want NULL.
    if (name == "btw_tool_env_describe_environment") {
      if (identical(args$items, list())) {
        args$items <- NULL
      }
    }

    tool_call_result <- do.call(fn, args)
    # cat(paste(capture.output(str(body)), collapse="\n"), file=stderr())

    body <- jsonrpc_response(
      data$id,
      list(
        content = list(
          list(
            type = "text",
            text = paste(tool_call_result, collapse = "\n")
          )
        ),
        isError = FALSE
      )
    )
  } else {
    body <- jsonrpc_response(
      dat$id,
      error = list(code = -32601, message = "Method not found")
    )
  }
  # cat(to_json(body), file = stderr())

  # cat("Request received at ", format(Sys.time(), "%H:%M:%S.%OS3\n"), file=stderr())

  list(
    status = 200L,
    headers = list('Content-Type' = 'application/json'),
    body = to_json(body)
  )
}


# Create a jsonrpc-structured response object.
jsonrpc_response <- function(id, result = NULL, error = NULL) {
  if (!xor(is.null(result), is.null(error))) {
    warning("Either `result` or `error` must be provided, but not both.")
  }

  drop_nulls(list(
    jsonrpc = "2.0",
    id = id,
    result = result,
    error = error
  ))
}

to_json <- function(x, ...) {
  jsonlite::toJSON(x, ..., auto_unbox = TRUE)
}

# Create a named list, ensuring that it's a named list, even if empty.
named_list <- function(...) {
  res <- list(...)
  if (length(res) == 0) {
    # A way of creating an empty named list
    res <- list(a = 1)[0]
  }
  res
}

# Given a vector or list, drop all the NULL items in it
drop_nulls <- function(x) {
  x[!vapply(x, is.null, FUN.VALUE=logical(1))]
}
