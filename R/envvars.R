mcptools_log_file <- function() {
  Sys.getenv("mcptools_LOG_FILE", tempfile(fileext = ".txt"))
}
