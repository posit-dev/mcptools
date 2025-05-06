acquaint_log_file <- function() {
  Sys.getenv("ACQUAINT_LOG_FILE", tempfile(fileext = ".txt"))
}
