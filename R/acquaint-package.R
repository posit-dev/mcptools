#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @import rlang
## usethis namespace: end
NULL

.onLoad <- function(libname, pkgname) {
  acquaint_socket <<- switch(
    Sys.info()[["sysname"]],
    Linux = "abstract://acquaint-socket",
    Windows = "ipc://acquaint-socket",
    "ipc:///tmp/acquaint-socket"
  )
}
