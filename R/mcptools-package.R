#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @import rlang
## usethis namespace: end
NULL

.onLoad <- function(libname, pkgname) {
  the$socket_url <- switch(
    Sys.info()[["sysname"]],
    Linux = "abstract://mcptools-socket",
    Windows = "ipc://mcptools-socket",
    "ipc:///tmp/mcptools-socket"
  )
}
