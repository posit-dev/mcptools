acquaint_port <- function(call = caller_env()) {
  port <- Sys.getenv("ACQUAINT_PORT", "8000")

  tryCatch(
    return(as.numeric(port)),
    error = function(e) {
      cli::cli_abort(
        c("{.env ACQUAINT_PORT} must be coercible to a number."),
        call = call
      )
    }
  )
}

acquaint_log_file <- function() {
  Sys.getenv("ACQUAINT_LOG_FILE", tempfile(fileext = ".txt"))
}
