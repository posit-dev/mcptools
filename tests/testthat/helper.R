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

local_streamable_http_mock_server <- function(
  post_sse = FALSE,
  require_bearer = FALSE,
  bearer_token = "mock-token",
  env = parent.frame()
) {
  port <- httpuv::randomPort()
  log_file <- withr::local_tempfile(fileext = ".ndjson", .local_envir = env)
  config_file <- withr::local_tempfile(fileext = ".json", .local_envir = env)
  script_file <- test_path("fixtures", "streamable-http-mock-server.R")

  jsonlite::write_json(
    list(
      protocol_version = latest_protocol_version,
      session_id = "session-1",
      post_sse = post_sse,
      require_bearer = require_bearer,
      bearer_token = bearer_token
    ),
    config_file,
    auto_unbox = TRUE,
    null = "null"
  )

  process <- processx::process$new(
    command = rscript_binary(),
    args = c(script_file, as.character(port), log_file, config_file),
    stdout = "|",
    stderr = "|"
  )
  withr::defer(process$kill(), envir = env)

  wait_for_streamable_http_mock_server(process, port)

  structure(
    list(
      url = sprintf("http://127.0.0.1:%d/mcp", port),
      process = process,
      log_file = log_file,
      requests = function() streamable_http_mock_server_requests(log_file)
    ),
    class = "streamable_http_mock_server"
  )
}

wait_for_streamable_http_mock_server <- function(process, port) {
  url <- sprintf("http://127.0.0.1:%d/health", port)
  deadline <- Sys.time() + 5

  repeat {
    if (!process$is_alive()) {
      cli::cli_abort(c(
        "Streamable HTTP mock server failed to start.",
        i = "stdout: {process$read_all_output()}",
        i = "stderr: {process$read_all_error()}"
      ))
    }

    resp <- tryCatch(
      httr2::request(url) |>
        httr2::req_timeout(1) |>
        httr2::req_perform(),
      error = function(err) NULL
    )
    if (!is.null(resp) && identical(httr2::resp_status(resp), 204L)) {
      return(invisible(process))
    }

    if (Sys.time() > deadline) {
      cli::cli_abort("Timed out waiting for Streamable HTTP mock server.")
    }

    Sys.sleep(0.05)
  }
}

streamable_http_mock_server_requests <- function(log_file) {
  if (!file.exists(log_file)) {
    return(list())
  }

  lines <- readLines(log_file, warn = FALSE)
  lapply(lines, jsonlite::parse_json, simplifyVector = FALSE)
}
