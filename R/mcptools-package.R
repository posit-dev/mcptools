# nocov start
#' @keywords internal
"_PACKAGE"

## usethis namespace: start
#' @import rlang
#' @importFrom stats setNames
## usethis namespace: end
NULL

.onLoad <- function(libname, pkgname) {
  the$socket_url <- socket_url()
  mcp_run_registrars(pkgname)
}

.onUnload <- function(libpath) {
  cleanup_session_socket()
}
# nocov end
