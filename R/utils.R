acquaint_env <- new_environment()

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
  jsonlite::toJSON(x, ..., auto_unbox = TRUE)
}

interactive <- NULL
