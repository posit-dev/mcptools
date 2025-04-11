mcp_enable <- function(port = 8081) {
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
  
  invisible(server)
}
