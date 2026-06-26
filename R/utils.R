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

# Create a named list, ensuring that it's a named list, even if empty.
named_list <- function(...) {
  res <- list(...)
  if (length(res) == 0) {
    # A way of creating an empty named list
    res <- list(a = 1)[0]
  }
  res
}

to_json <- function(x, ...) {
  jsonlite::toJSON(x, ..., auto_unbox = TRUE, null = "null")
}

is_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}

is_absolute_path <- function(path) {
  grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)
}

split_envvar <- function(x) {
  if (!nzchar(x)) {
    return(character())
  }

  trimws(strsplit(x, ",", fixed = TRUE)[[1]])
}

first_nonempty_string <- function(...) {
  for (x in list(...)) {
    if (is_string(x) && nzchar(x)) {
      return(x)
    }
  }

  ""
}

url_origin <- function(x) {
  parsed <- url_parse_or_null(x)
  if (is.null(parsed$scheme) || is.null(parsed$hostname)) {
    return(NULL)
  }

  host <- parsed$hostname
  if (!is.null(parsed$port)) {
    host <- paste0(host, ":", parsed$port)
  }

  paste0(parsed$scheme, "://", host)
}

url_parse_or_null <- function(x) {
  tryCatch(
    httr2::url_parse(x),
    error = function(err) NULL
  )
}

constant_time_equal <- function(x, y) {
  if (!is_string(x) || !is_string(y)) {
    return(FALSE)
  }

  x <- as.integer(charToRaw(enc2utf8(x)))
  y <- as.integer(charToRaw(enc2utf8(y)))
  n <- max(length(x), length(y))
  diff <- bitwXor(length(x), length(y))

  for (i in seq_len(n)) {
    x_i <- if (i <= length(x)) x[[i]] else 0L
    y_i <- if (i <= length(y)) y[[i]] else 0L
    diff <- bitwOr(diff, bitwXor(x_i, y_i))
  }

  identical(diff, 0L)
}

interactive <- NULL

mcptools_server_log <- function() {
  Sys.getenv("MCPTOOLS_SERVER_LOG", tempfile(fileext = ".txt"))
}

mcptools_client_log <- function() {
  Sys.getenv("MCPTOOLS_CLIENT_LOG", tempfile(fileext = ".txt"))
}

# from rstudio/reticulate
is_unix <- function() {
  identical(.Platform$OS.type, "unix")
}

is_fedora <- function() {
  if (is_unix() && file.exists("/etc/os-release")) {
    os_info <- readLines("/etc/os-release")
    any(grepl("Fedora", os_info))
  } else {
    FALSE
  }
}
