#' Start an MCP server for your R session
#' @export
mcp_enable <- function(port = 8081) {
  tryCatch({
    existing_server <- httpuv::listServers()
    if (length(existing_server) > 0) {
      httpuv::stopServer(existing_server[[1]])
    }
  }, error = function(cnd) {
    cli::cli_abort(
      "Unable to terminate the existing server.",
      parent = cnd,
      call = call
    )
  })

  server <- httpuv::startServer(
    host = "127.0.0.1",
    port = port,
    app = list(
      call = function(req) {
        if (req$REQUEST_METHOD == "POST") {
          body_chars <- rawToChar(req$rook.input$read())
          result <- tryCatch({
            output <- capture.output({
              eval_result <- eval(parse(text = body_chars), envir = rlang::env())
            })
            
            if (is.null(eval_result)) {
              result_text <- paste(output, collapse = "\n")
            } else {
              if (is.character(eval_result) && length(eval_result) == 1) {
                result_text <- eval_result
              } else {
                result_text <- paste(c(output, capture.output(print(eval_result))), collapse = "\n")
              }
            }
            
            list(
              status = 200L,
              headers = list('Content-Type' = 'text/plain'),
              body = result_text
            )
          }, error = function(e) {
            list(
              status = 500L,
              headers = list('Content-Type' = 'text/plain'),
              body = paste("Error:", e$message)
            )
          })
          
          return(result)
        } else {
          return(list(
            status = 405L,
            headers = list('Content-Type' = 'text/plain'),
            body = "Method not allowed"
          ))
        }
      }
    )
  )
  
  url <- sprintf("http://%s:%d", host, port)
  cli::cli_inform(
    c("v" = "R session server running at: {.url {url}}"),
    class = "acquaint_viewer_start"
  )

  invisible(server)
}
