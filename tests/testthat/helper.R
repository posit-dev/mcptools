on_windows <- function() {
  isTRUE(Sys.info()[['sysname']] == "Windows")
}

rscript_binary <- function() {
  if (on_windows()) {
    return(file.path(R.home("bin"), "Rscript.exe"))
  }

  file.path(R.home("bin"), "Rscript")
}

local_protocol_version <- function(
  protocol_version = the$protocol_version,
  env = parent.frame()
) {
  old_protocol_version <- the$protocol_version
  withr::defer(the$protocol_version <- old_protocol_version, envir = env)

  the$protocol_version <- protocol_version
  invisible(protocol_version)
}

local_http_security <- function(
  allowed_origins = character(),
  trusted_hosts = character(),
  shared_secret = NULL,
  env = parent.frame()
) {
  old_allowed_origins <- the$http_allowed_origins
  old_trusted_hosts <- the$http_trusted_hosts
  old_shared_secret <- the$http_shared_secret

  withr::defer(
    {
      the$http_allowed_origins <- old_allowed_origins
      the$http_trusted_hosts <- old_trusted_hosts
      the$http_shared_secret <- old_shared_secret
    },
    envir = env
  )

  the$http_allowed_origins <- allowed_origins
  the$http_trusted_hosts <- trusted_hosts
  the$http_shared_secret <- shared_secret

  invisible()
}
