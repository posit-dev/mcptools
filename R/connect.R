launch_server <- function(settings, host = NULL, port = NULL, ...) {
  server_file <- settings
  config <- read_connect_server_config(server_file)
  configure_connect_http_security()

  args <- list(
    tools = config$tools,
    type = "http",
    session_tools = config$session_tools
  )

  if (!is.null(host)) {
    args$host <- host
  }
  if (!is.null(port)) {
    args$port <- port
  }

  do.call(mcp_server, args)
}

read_connect_server_config <- function(server_file, call = caller_env()) {
  if (!is_string(server_file) || !file.exists(server_file)) {
    cli::cli_abort(
      "{.arg server_file} must be a single existing file path.",
      call = call
    )
  }

  config <- yaml::read_yaml(server_file)
  if (!is.list(config)) {
    cli::cli_abort(
      "{.file {basename(server_file)}} must be a YAML mapping.",
      call = call
    )
  }

  engine <- config$engine %||% ""
  if (!identical(engine, "mcptools")) {
    cli::cli_abort(
      "{.file {basename(server_file)}} must specify {.code engine: mcptools}.",
      call = call
    )
  }

  tools <- config$tools %||% NULL
  if (!is.null(tools)) {
    tools <- resolve_connect_tools_path(tools, server_file, call = call)
  }

  session_tools <- config$session_tools %||% FALSE
  if (
    !is.logical(session_tools) ||
      length(session_tools) != 1L ||
      is.na(session_tools)
  ) {
    cli::cli_abort(
      "{.field session_tools} must be {.code true} or {.code false}.",
      call = call
    )
  }

  list(
    tools = tools,
    session_tools = session_tools
  )
}

resolve_connect_tools_path <- function(
  tools,
  server_file,
  call = caller_env()
) {
  if (!is_string(tools)) {
    cli::cli_abort(
      "{.field tools} must be a single file path.",
      call = call
    )
  }

  if (!grepl("\\.r$", tools, ignore.case = TRUE)) {
    cli::cli_abort(
      "{.field tools} must point to an {.file .R} file.",
      call = call
    )
  }

  if (!is_absolute_path(tools)) {
    tools <- file.path(dirname(server_file), tools)
  }

  if (!file.exists(tools)) {
    cli::cli_abort(
      "The {.field tools} file {.file {tools}} does not exist.",
      call = call
    )
  }

  normalizePath(tools, mustWork = TRUE)
}

configure_connect_http_security <- function() {
  origin <- connect_server_origin()
  the$http_allowed_origins <- origin %||% character()
  the$http_trusted_hosts <- character()
  invisible()
}

connect_server_origin <- function() {
  connect_server <- Sys.getenv("CONNECT_SERVER", "")
  if (!nzchar(connect_server)) {
    return(NULL)
  }

  url_origin(connect_server)
}
