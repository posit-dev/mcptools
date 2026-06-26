# This file implements R as the _client_.

# tools ------------------------------------------------------------------------
# each named entry is:
# name: the name of the server (from the config)
# transport: the MCP transport object
# tools: a named list of tools
# id: the next jsonrpc message id
the$mcp_servers <- list()

#' R as a client: Define ellmer tools from MCP servers
#'
#' @description
#' These functions implement R as an MCP _client_, so that ellmer chats can
#' register functionality from third-party MCP servers such as those listed
#' here: <https://github.com/modelcontextprotocol/servers>.
#'
#' `mcp_tools()` fetches tools from MCP servers configured in the mcptools
#' server config file and converts them to a list of
#' tools compatible with the `$set_tools()` method of [ellmer::Chat] objects.
#'
#' @param config A single string indicating the path to the mcptools MCP servers
#' configuration file. If one is not supplied, mcptools will look for one at
#' the file path configured with the option `.mcptools_config`, falling back to
#' `file.path("~", ".config", "mcptools", "config.json")`.
#'
#' @seealso
#' This function implements R as an MCP _client_. To use R as an MCP _server_,
#' i.e. to provide apps like Claude Desktop or Claude Code with access to
#' R-based tools, see [mcp_server()].
#'
#' @section Configuration:
#'
#' mcptools uses the same .json configuration file format as Claude Desktop;
#' most MCP servers will define example .json to configure the server with
#' Claude Desktop in their README files. By default, mcptools will look to
#' `file.path("~", ".config", "mcptools", "config.json")`; you can edit that
#' file with `file.edit(file.path("~", ".config", "mcptools", "config.json"))`.
#'
#' The mcptools config file should be valid .json with an entry `mcpServers`.
#' That entry should contain named elements, each configuring either a local
#' stdio server with `command` and `args`, or a remote Streamable HTTP server
#' with `url`. Stdio MCP server processes receive an allowlisted environment
#' inherited from the current R process, plus any variables configured in
#' `env`. Configured `env` variables override inherited variables with the same
#' name. Servers that need additional environment variables should list them in
#' `env`.
#'
#' For example, to configure `mcp_tools()` with GitHub's official MCP Server
#' <https://github.com/github/github-mcp-server>, you could write the following
#' in that file:
#'
#' ```json
#' {
#'   "mcpServers": {
#'     "github": {
#'       "command": "docker",
#'       "args": [
#'         "run",
#'         "-i",
#'         "--rm",
#'         "-e",
#'         "GITHUB_PERSONAL_ACCESS_TOKEN",
#'         "ghcr.io/github/github-mcp-server"
#'       ],
#'       "env": {
#'         "GITHUB_PERSONAL_ACCESS_TOKEN": "<add_your_github_pat_here>"
#'       }
#'     }
#'   }
#' }
#' ```
#'
#' @section Connecting to remote (http) servers:
#' For remote Streamable HTTP MCP servers, configure a server with `url`.
#' Static headers can be supplied with `headers`; protocol-owned headers such
#' as `Accept`, `Content-Type`, `MCP-Session-Id`, and `MCP-Protocol-Version`
#' are managed by mcptools and cannot be configured manually. Credentialed
#' public remote endpoints must use HTTPS. HTTP is allowed for loopback
#' development servers, or for explicit unsafe opt-out with `allow_http`.
#'
#' Remote server entries support these fields:
#'
#' * `url`: the Streamable HTTP MCP endpoint.
#' * `headers`: named static headers. Values may use `${ENVVAR}` interpolation.
#' * `timeout`: a number of seconds for the overall HTTP request timeout.
#' * `allow_http`: allow credentialed non-loopback HTTP endpoints.
#' * `ignore_tools`: tool names or `*` wildcards to hide and block.
#' * `oauth`: OAuth settings.
#'
#' OAuth settings may include `authorization_server`, `resource`, `scope` with
#' `scope_mode = "override"`, `client_info`, `manual_client_info`,
#' `client_metadata`, `redirect_uri` or `callback_host`/`callback_port`/
#' `callback_path`, `cache_dir`, and `allow_http`. mcptools supports OAuth 2.1
#' with PKCE: it discovers the authorization server from the protected-resource
#' metadata advertised in a `401` challenge, registers a client dynamically when
#' the server supports it, and caches tokens (refreshing them automatically).
#'
#' Remote HTTP requests use httr2 and curl. Proxy and corporate CA settings
#' should generally use the standard curl environment variables, such as
#' `HTTPS_PROXY`, `NO_PROXY`, `SSL_CERT_FILE`, and `CURL_CA_BUNDLE`. Stdio
#' server processes inherit these variables through mcptools' default
#' environment allowlist.
#'
#' ```json
#' {
#'   "mcpServers": {
#'     "remote-example": {
#'       "url": "https://remote.mcp.server/mcp",
#'       "timeout": 30,
#'       "headers": {
#'         "Authorization": "Bearer ${REMOTE_MCP_TOKEN}"
#'       }
#'     }
#'   }
#' }
#' ```
#'
#' @returns
#' `mcp_tools()` returns a list of ellmer tools that can be passed directly
#' to the `$set_tools()` method of an [ellmer::Chat] object. If the file at
#' `config` doesn't exist, an error.
#'
#' @examples
#' # setup
#' config_file <- tempfile(fileext = "json")
#' file.create(config_file)
#'
#' # usually, `config` would be a persistent, user-level
#' # configuration file for a set of MCP server
#' mcp_tools(config = config_file)
#'
#' # teardown
#' file.remove(config_file)
#'
#'
#' @name client
#' @aliases mcp_client
#' @export
mcp_tools <- function(config = NULL) {
  if (is.null(config)) {
    config <- mcp_client_config()
  }

  config <- read_mcp_config(config)
  if (length(config) == 0) {
    return(list())
  }

  for (i in seq_along(config)) {
    config_i <- config[[i]]
    name_i <- names(config)[i]

    add_mcp_server(config = config_i, name = name_i)
  }

  servers_as_ellmer_tools()
}

mcp_client_config <- function() {
  getOption(
    ".mcptools_config",
    default = default_mcp_client_config()
  )
}

default_mcp_client_config <- function() {
  file.path("~", ".config", "mcptools", "config.json")
}

read_mcp_config <- function(config, call = caller_env()) {
  if (!file.exists(config)) {
    error_no_mcp_config(call = call)
  }

  config_lines <- readLines(config)
  if (length(config_lines) == 0) {
    return(list())
  }

  tryCatch(
    {
      config <- jsonlite::fromJSON(config_lines)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Configuration processing failed",
          i = "The configuration file {.arg config} must be valid JSON."
        ),
        call = call,
        parent = e
      )
    }
  )

  if (!"mcpServers" %in% names(config)) {
    cli::cli_abort(
      c(
        "Configuration processing failed.",
        i = "{.arg config} must have a top-level {.field mcpServers} entry."
      ),
      call = call
    )
  }

  config$mcpServers
}

error_no_mcp_config <- function(call) {
  cli::cli_abort(
    c(
      "The mcptools MCP client configuration file does not exist.",
      i = "Supply a non-NULL file {.arg config} or create a file at the default
           configuration location {.file {default_mcp_client_config()}}."
    ),
    call = call
  )
}

add_mcp_server <- function(config, name, call = caller_env()) {
  if (name %in% names(the$mcp_servers)) {
    mcp_transport_close(the$mcp_servers[[name]]$transport, call = call)
    the$mcp_servers[[name]] <- NULL
  }

  transport <- mcp_transport(config, call = call)
  ignore_tools <- mcp_ignore_tools(config$ignore_tools %||% character(), call = call)

  if (identical(transport$type, "stdio")) {
    process <- transport$process
    the$server_processes <- c(
      the$server_processes,
      list2(
        !!paste0(
          c(config$command, config$args %||% ""),
          collapse = " "
        ) := process
      )
    )
  }

  next_id <- 1L

  # Fail gracefully if the process failed on startup (#82)
  tryCatch(
    {
      response_initialize <- mcp_transport_request(
        transport,
        mcp_request_initialize(id = next_id)
      )
      next_id <- next_id + 1L
      mcp_transport_store_initialize(transport, response_initialize, call = call)

      mcp_transport_notify(transport, mcp_request_initialized())

      tools_list <- mcp_request_tools_list_all(transport, next_id, call = call)
      response_tools_list <- tools_list$response
      response_tools_list$result$tools <- mcp_filter_tools(
        response_tools_list$result$tools,
        ignore_tools,
        call = call
      )
      next_id <- tools_list$next_id
    },
    error = function(e) {
      if (
        identical(transport$type, "stdio") &&
          process$get_exit_status() %in% c(1L, 2L)
      ) {
        cli::cli_abort(
          c(
            "The command {.code {config$command}} failed with the following error:",
            "x" = "{paste0(mcp_process_error_lines(process), collapse = '. ')}"
          ),
          call = call
        )
      }

      cnd_signal(e)
    }
  )

  the$mcp_servers[[name]] <- list(
    name = name,
    type = transport$type,
    transport = transport,
    process = transport$process,
    tools = response_tools_list$result,
    ignore_tools = ignore_tools,
    id = next_id
  )

  the$mcp_servers[[name]]
}

# transports -------------------------------------------------------------------
mcp_transport <- function(config, call = caller_env()) {
  if (!is.null(config$url)) {
    return(mcp_transport_http(config, call = call))
  }

  mcp_transport_stdio(config, call = call)
}

mcp_transport_stdio <- function(config, call = caller_env()) {
  if (is.null(config$command)) {
    cli::cli_abort(
      c(
        "MCP server configuration failed.",
        i = "Each server must have either {.field url} or {.field command}."
      ),
      call = call
    )
  }

  process <- processx::process$new(
    command = Sys.which(config$command),
    args = config$args %||% character(),
    env = mcp_server_env(config),
    stdin = "|",
    stdout = "|",
    stderr = "|"
  )

  rlang::env(
    type = "stdio",
    process = process
  )
}

mcp_transport_http <- function(config, call = caller_env()) {
  if (!is_string(config$url)) {
    cli::cli_abort(
      c(
        "MCP HTTP server configuration failed.",
        i = "{.field url} must be a single string."
      ),
      call = call
    )
  }

  oauth <- mcp_config_oauth(config, call = call)
  headers <- mcp_config_headers(
    config$headers %||% list(),
    oauth = oauth,
    call = call
  )
  allow_http <- mcp_config_allow_http(config, call = call)
  timeout <- mcp_config_timeout(config$timeout %||% NULL, call = call)

  mcp_validate_http_endpoint_security(
    config$url,
    headers = headers,
    oauth = oauth,
    allow_http = allow_http,
    call = call
  )

  rlang::env(
    type = "http",
    process = NULL,
    url = config$url,
    headers = headers,
    timeout = timeout,
    allow_http = allow_http,
    oauth = oauth,
    session_id = NULL,
    protocol_version = NULL,
    http_request_active = FALSE,
    oauth_metadata = NULL,
    oauth_client_info = NULL,
    oauth_scope = NULL,
    oauth_token = NULL,
    oauth_cache_key = NULL
  )
}

mcp_transport_request <- function(transport, message, call = caller_env()) {
  if (identical(transport$type, "http")) {
    return(mcp_transport_http_send(
      transport,
      message,
      expect_response = TRUE,
      call = call
    ))
  }

  mcp_transport_stdio_send(transport, message, expect_response = TRUE)
}

mcp_transport_notify <- function(transport, message, call = caller_env()) {
  if (identical(transport$type, "http")) {
    return(mcp_transport_http_send(transport, message, expect_response = FALSE, call = call))
  }

  mcp_transport_stdio_send(transport, message, expect_response = FALSE)
}

mcp_transport_close <- function(transport, call = caller_env()) {
  if (identical(transport$type, "http")) {
    return(mcp_transport_http_close(transport, call = call))
  }

  mcp_transport_stdio_close(transport)
}

# config -----------------------------------------------------------------------
mcp_config_headers <- function(headers, oauth = list(), call = caller_env()) {
  if (length(headers) == 0) {
    return(character())
  }

  headers <- unlist(headers, use.names = TRUE)

  if (is.null(names(headers)) || any(!nzchar(names(headers)))) {
    cli::cli_abort(
      c(
        "MCP HTTP server configuration failed.",
        i = "{.field headers} must be a named object."
      ),
      call = call
    )
  }

  header_names <- names(headers)
  reserved_headers <- c(
    "accept",
    "content-type",
    "mcp-session-id",
    "mcp-protocol-version"
  )
  reserved <- intersect(tolower(header_names), reserved_headers)

  if (length(reserved) > 0) {
    reserved_header <- header_names[tolower(header_names) == reserved[[1]]][[1]]
    cli::cli_abort(
      c(
        "MCP HTTP server configuration failed.",
        i = "{.field headers.{reserved_header}} is managed by mcptools and cannot be configured manually."
      ),
      call = call
    )
  }

  if (
    any(tolower(header_names) == "authorization") &&
      length(oauth) > 0 &&
      !isTRUE(oauth$allow_authorization_header)
  ) {
    cli::cli_abort(
      c(
        "MCP HTTP server configuration failed.",
        i = "{.field headers.Authorization} and {.field oauth} both configure authorization.",
        i = "Remove one of them or set {.field oauth.allow_authorization_header} to {.code true}."
      ),
      call = call
    )
  }

  headers <- vapply(
    as.character(headers),
    mcp_interpolate_env,
    character(1),
    call = call
  )
  names(headers) <- header_names
  headers
}

mcp_config_allow_http <- function(config, call = caller_env()) {
  allow_http <- config$allow_http %||%
    config$oauth$allow_http %||%
    FALSE

  if (!is.logical(allow_http) || length(allow_http) != 1L || is.na(allow_http)) {
    cli::cli_abort(
      c(
        "MCP HTTP server configuration failed.",
        i = "{.field allow_http} must be {.code true} or {.code false}."
      ),
      call = call
    )
  }

  isTRUE(allow_http)
}

mcp_config_timeout <- function(timeout, call = caller_env()) {
  if (is.null(timeout)) {
    return(NULL)
  }

  if (!is.numeric(timeout) || length(timeout) != 1L || is.na(timeout) || timeout <= 0) {
    cli::cli_abort(
      c(
        "MCP HTTP server configuration failed.",
        i = "{.field timeout} must be a single positive number of seconds."
      ),
      call = call
    )
  }

  timeout
}

mcp_validate_http_endpoint_security <- function(
  url,
  headers = character(),
  oauth = list(),
  allow_http = FALSE,
  call = caller_env()
) {
  parsed <- url_parse_or_null(url)
  if (is.null(parsed) || is.null(parsed$scheme) || is.null(parsed$hostname)) {
    return(invisible(TRUE))
  }

  scheme <- tolower(parsed$scheme)
  host <- tolower(parsed$hostname)

  if (!identical(scheme, "http")) {
    return(invisible(TRUE))
  }

  if (mcp_oauth_is_loopback_host(host) || isTRUE(allow_http)) {
    return(invisible(TRUE))
  }

  if (length(headers) == 0 && length(oauth) == 0) {
    return(invisible(TRUE))
  }

  cli::cli_abort(
    c(
      "MCP HTTP server configuration failed.",
      i = "Credentialed remote MCP endpoints must use HTTPS unless {.field allow_http} is {.code true}.",
      i = "Endpoint: {.url {url}}."
    ),
    call = call
  )
}

mcp_interpolate_env <- function(x, call = caller_env()) {
  matches <- gregexpr(
    "\\$\\{([A-Za-z_][A-Za-z0-9_]*)\\}",
    x,
    perl = TRUE
  )[[1]]

  if (identical(matches[[1]], -1L)) {
    return(x)
  }

  tokens <- regmatches(x, list(matches))[[1]]
  vars <- sub("^\\$\\{", "", sub("\\}$", "", tokens))
  values <- Sys.getenv(vars, unset = NA_character_)

  if (any(is.na(values))) {
    cli::cli_abort(
      c(
        "MCP server configuration failed.",
        i = "Environment variable {.envvar {vars[is.na(values)][[1]]}} is not set."
      ),
      call = call
    )
  }

  for (i in seq_along(tokens)) {
    x <- gsub(tokens[[i]], values[[i]], x, fixed = TRUE)
  }

  x
}

mcp_config_interpolate_env <- function(x, call = caller_env()) {
  if (is.character(x)) {
    return(vapply(
      x,
      mcp_interpolate_env,
      character(1),
      call = call,
      USE.NAMES = FALSE
    ))
  }

  if (is.list(x)) {
    return(lapply(x, mcp_config_interpolate_env, call = call))
  }

  x
}

mcp_config_oauth <- function(config, call = caller_env()) {
  oauth <- mcp_config_interpolate_env(config$oauth %||% list(), call = call)

  if (length(oauth) == 0) {
    return(named_list())
  }

  scope <- oauth$scope %||% NULL
  scope_mode <- oauth$scope_mode %||% NULL
  if (!is.null(scope) && !identical(scope_mode, "override")) {
    cli::cli_abort(
      c(
        "MCP OAuth configuration failed.",
        i = "{.field oauth.scope} is only supported when {.field oauth.scope_mode} is {.val override}."
      ),
      call = call
    )
  }

  # the resource indicator defaults to the server URL when not configured
  resource <- oauth$resource %||% config$url %||% NULL
  if (!is.null(resource)) {
    resource <- mcp_oauth_resource(resource, call = call)
  }

  oauth <- named_list(
    authorization_server = oauth$authorization_server %||% NULL,
    resource = resource,
    scope = scope,
    scope_mode = scope_mode,
    client_info = oauth$client_info %||% NULL,
    manual_client_info = oauth$manual_client_info %||% NULL,
    client_metadata = oauth$client_metadata %||% NULL,
    allow_authorization_header = oauth$allow_authorization_header %||% NULL,
    redirect_uri = oauth$redirect_uri %||% NULL,
    callback_host = oauth$callback_host %||% "localhost",
    callback_port = mcp_config_oauth_callback_port(
      oauth$callback_port %||% 1410L,
      call = call
    ),
    callback_path = oauth$callback_path %||% "/oauth/callback",
    cache_dir = oauth$cache_dir %||%
      file.path(tools::R_user_dir("mcptools", "cache"), "oauth")
  )

  mcp_validate_oauth_redirect_uri(mcp_oauth_redirect_uri(oauth), call = call)
  oauth
}

mcp_config_oauth_callback_port <- function(callback_port, call = caller_env()) {
  callback_port <- unlist(callback_port, use.names = FALSE)[[1]]
  if (
    !is.numeric(callback_port) ||
      is.na(callback_port) ||
      callback_port != as.integer(callback_port) ||
      callback_port < 1L ||
      callback_port > 65535L
  ) {
    cli::cli_abort(
      c(
        "MCP OAuth configuration failed.",
        i = "{.field oauth.callback_port} must be an integer TCP port between 1 and 65535."
      ),
      call = call
    )
  }

  as.integer(callback_port)
}

# initialize and tool listing -------------------------------------------------
mcp_transport_store_initialize <- function(transport, response, call = caller_env()) {
  if (!is.null(response$error)) {
    cli::cli_abort(
      response$error$message %||% "MCP initialize failed.",
      call = call
    )
  }

  if (is.null(response$result)) {
    cli::cli_abort(
      "MCP initialize returned no result.",
      call = call
    )
  }

  protocol_version <- response$result$protocolVersion %||% latest_protocol_version

  if (!protocol_version %in% supported_protocol_versions) {
    cli::cli_abort(
      c(
        "MCP server negotiated an unsupported protocol version.",
        i = "Server version: {.val {protocol_version}}.",
        i = "Supported versions: {.val {supported_protocol_versions}}."
      ),
      call = call
    )
  }

  transport$protocol_version <- protocol_version
  invisible(transport)
}

mcp_request_tools_list_all <- function(transport, id, call = caller_env()) {
  tools <- list()
  next_cursor <- NULL

  repeat {
    response <- mcp_transport_request(
      transport,
      mcp_request_tools_list(id = id, cursor = next_cursor)
    )
    id <- id + 1L

    if (!is.null(response$error)) {
      cli::cli_abort(
        response$error$message %||% "MCP tools/list failed.",
        call = call
      )
    }

    tools <- c(tools, response$result$tools %||% list())
    next_cursor <- response$result$nextCursor

    if (is.null(next_cursor) || !nzchar(next_cursor)) {
      break
    }
  }

  response$result$tools <- tools

  list(
    response = response,
    next_id = id
  )
}

mcp_ignore_tools <- function(ignore_tools = character(), call = caller_env()) {
  if (length(ignore_tools) == 0) {
    return(character())
  }

  ignore_tools <- unlist(ignore_tools, use.names = FALSE)
  if (!is.character(ignore_tools)) {
    cli::cli_abort(
      c(
        "MCP server configuration failed.",
        i = "{.field ignore_tools} must be a character vector."
      ),
      call = call
    )
  }

  ignore_tools
}

mcp_filter_tools <- function(tools, ignore_tools = character(), call = caller_env()) {
  ignore_tools <- mcp_ignore_tools(ignore_tools, call = call)
  if (length(ignore_tools) == 0) {
    return(tools)
  }

  tools[!vapply(
    tools,
    function(tool) mcp_tool_ignored(tool$name, ignore_tools),
    logical(1)
  )]
}

mcp_tool_ignored <- function(tool, ignore_tools = character()) {
  if (length(ignore_tools) == 0) {
    return(FALSE)
  }

  any(vapply(
    ignore_tools,
    function(pattern) {
      grepl(mcp_ignore_tool_pattern_regex(pattern), tool, ignore.case = TRUE)
    },
    logical(1)
  ))
}

mcp_ignore_tool_pattern_regex <- function(pattern) {
  escaped <- gsub("([\\^$.|?+(){}\\[\\]\\\\])", "\\\\\\1", pattern, perl = TRUE)
  paste0("^", gsub("*", ".*", escaped, fixed = TRUE), "$")
}

mcp_server_env <- function(config) {
  env <- mcp_inherited_env()

  if ("env" %in% names(config)) {
    configured <- unlist(config$env, use.names = TRUE)
    env[names(configured)] <- configured
  }

  env
}

mcp_inherited_env <- function() {
  env <- Sys.getenv(mcp_inherited_env_vars(), unset = NA_character_)
  env <- env[!is.na(env)]
  # Skip exported bash functions, which can trigger shellshock-style behavior.
  env[!startsWith(env, "()")]
}

mcp_process_error_lines <- function(process) {
  lines <- process$read_all_error_lines()
  lines[!grepl("^Ran [0-9]+/[0-9]+ deferred expressions$", lines)]
}

mcp_inherited_env_vars <- function() {
  platform_vars <- if (identical(.Platform$OS.type, "windows")) {
    c(
      "APPDATA", "HOMEDRIVE", "HOMEPATH", "LOCALAPPDATA", "PATH", "PATHEXT",
      "PROCESSOR_ARCHITECTURE", "SYSTEMDRIVE", "SYSTEMROOT", "TEMP", "TMP",
      "USERNAME", "USERPROFILE", "WINDIR"
    )
  } else {
    c("HOME", "LOGNAME", "PATH", "SHELL", "TERM", "TMPDIR", "USER")
  }

  unique(c(
    platform_vars,
    "R_HOME", "R_LIBS", "R_LIBS_USER", "R_LIBS_SITE", "R_PROFILE",
    "R_PROFILE_USER", "R_ENVIRON", "R_ENVIRON_USER", "R_USER", "TZ",
    "LANG", "LC_ALL", "LC_COLLATE", "LC_CTYPE", "LC_MESSAGES",
    "LC_MONETARY", "LC_NUMERIC", "LC_TIME", "LC_ADDRESS",
    "LC_IDENTIFICATION", "LC_MEASUREMENT", "LC_NAME", "LC_PAPER",
    "LC_TELEPHONE", "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "http_proxy",
    "https_proxy", "no_proxy", "SSL_CERT_FILE", "SSL_CERT_DIR",
    "CURL_CA_BUNDLE", "REQUESTS_CA_BUNDLE", "NODE_EXTRA_CA_CERTS",
    "JAVA_HOME"
  ))
}

# ellmer tools -----------------------------------------------------------------
servers_as_ellmer_tools <- function() {
  unname(unlist(
    lapply(the$mcp_servers, server_as_ellmer_tools),
    recursive = FALSE
  ))
}

server_as_ellmer_tools <- function(server) {
  tools <- server$tools$tools

  tools_out <- list()
  for (i in seq_along(tools)) {
    tool <- tools[[i]]
    tool_arguments <- as_ellmer_types(tool)
    tools_out[[i]] <- do.call(
      ellmer::tool,
      c(
        list(
          fun = tool_ref(
            server = server$name,
            tool = tool$name,
            arguments = names(tool_arguments)
          ),
          description = tool$description,
          arguments = tool_arguments,
          name = tool$name
        )
      )
    )
  }

  tools_out
}

as_ellmer_types <- function(tool) {
  properties <- tool$inputSchema$properties
  required_fields <- tool$inputSchema$required

  result <- list()
  for (prop_name in names(properties)) {
    result[[prop_name]] <- as_ellmer_type(
      prop_name,
      properties[[prop_name]],
      required_fields
    )
  }

  result
}

as_ellmer_type <- function(prop_name, prop_def, required_fields = character()) {
  type <- prop_def$type
  description <- prop_def$description
  is_required <- prop_name %in% required_fields

  schema_type <- as_ellmer_type_from_schema(prop_def, is_required)
  if (!is.null(schema_type)) {
    return(schema_type)
  }

  if (length(type) == 0) {
    return(NULL)
  }

  switch(
    type,
    "string" = ellmer::type_string(
      description = description,
      required = is_required
    ),
    "number" = ellmer::type_number(
      description = description,
      required = is_required
    ),
    "integer" = ellmer::type_integer(
      description = description,
      required = is_required
    ),
    "boolean" = ellmer::type_boolean(
      description = description,
      required = is_required
    ),
    "array" = {
      if (!is.null(prop_def$items)) {
        items_type <- as_ellmer_type("", prop_def$items, required_fields)
        ellmer::type_array(
          description = description,
          items = items_type,
          required = is_required
        )
      } else {
        ellmer::type_array(
          description = description,
          items = ellmer::type_string(),
          required = is_required
        )
      }
    },
    "object" = {
      if (!is.null(prop_def$properties)) {
        obj_args <- list(.description = description, .required = is_required)
        for (obj_prop_name in names(prop_def$properties)) {
          obj_args[[obj_prop_name]] <- as_ellmer_type(
            obj_prop_name,
            prop_def$properties[[obj_prop_name]],
            required_fields
          )
        }
        do.call(ellmer::type_object, obj_args)
      } else {
        ellmer::type_object(.description = description, .required = is_required)
      }
    },
    ellmer::type_string(description = description, required = is_required)
  )
}

as_ellmer_type_from_schema <- function(prop_def, required) {
  tryCatch(
    {
      res <- ellmer::type_from_schema(text = to_json(prop_def))
      if (inherits(res, "ellmer::Type")) {
        res@required <- required
      }
      res
    },
    error = function(err) NULL
  )
}

# the output of this function is the function that the ellmer tool will
# reference. it has the "right" argument formals and carries along the server
# and tool it's associated with; when the outputted function is called, it just
# invokes the right tool from `the$mcp_servers` with the supplied arguments
tool_ref <- function(server, tool, arguments) {
  f <- function() {}
  formals(f) <- setNames(
    rep(list(quote(expr = )), length(arguments)),
    arguments
  )

  body(f) <- substitute(
    {
      call_info <- match.call()
      tool_args <- lapply(call_info[-1], eval)
      do.call(
        call_tool,
        c(tool_args, list(server = server_val, tool = tool_val))
      )
    },
    list(server_val = server, tool_val = tool)
  )

  f
}

call_tool <- function(..., server, tool) {
  mcp_check_tool_not_ignored(server, tool)

  id <- jsonrpc_id(server)
  request <- mcp_request_tool_call(id = id, tool = tool, arguments = list(...))

  response <- mcp_server_request_cancellable(server, request)

  mcp_tool_result_as_ellmer(response)
}

mcp_server_request_cancellable <- function(server, request, call = caller_env()) {
  tryCatch(
    mcp_server_request(server, request, call = call),
    interrupt = function(err) {
      mcp_send_cancelled_notification(
        server = server,
        request = request,
        reason = "User interrupted the request.",
        call = call
      )
      stop(err)
    }
  )
}

mcp_send_cancelled_notification <- function(
  server,
  request,
  reason = "Request cancelled.",
  call = caller_env()
) {
  if (identical(request$method, "initialize")) {
    return(FALSE)
  }

  tryCatch(
    {
      mcp_transport_notify(
        the$mcp_servers[[server]]$transport,
        mcp_request_cancelled(request$id, reason = reason),
        call = call
      )
      TRUE
    },
    error = function(err) FALSE
  )
}

mcp_check_tool_not_ignored <- function(server, tool, call = caller_env()) {
  ignore_tools <- the$mcp_servers[[server]]$ignore_tools %||% character()
  if (!mcp_tool_ignored(tool, ignore_tools)) {
    return(invisible(TRUE))
  }

  cli::cli_abort(
    "MCP tool is ignored and cannot be called: {.val {tool}}.",
    call = call
  )
}

mcp_server_request <- function(server, message, call = caller_env()) {
  server_entry <- the$mcp_servers[[server]]

  mcp_transport_request(server_entry$transport, message, call = call)
}

mcp_tool_result_as_ellmer <- function(response) {
  if (is.null(response)) {
    return(NULL)
  }

  if (!is.null(response$error)) {
    mcp_abort_jsonrpc_error(response$error)
  }

  result <- response$result
  if (is.null(result$content) && is.null(result$structuredContent)) {
    return(result)
  }

  content <- lapply(result$content %||% list(), mcp_content_as_ellmer)

  if (isTRUE(result$isError)) {
    return(ellmer::ContentToolResult(
      error = mcp_content_as_text(result$content)
    ))
  }

  if (!is.null(result$structuredContent)) {
    if (length(content) == 0) {
      return(result$structuredContent)
    }

    return(ellmer::ContentToolResult(
      value = result$structuredContent,
      extra = list(content = content)
    ))
  }

  if (all(vapply(result$content, function(block) {
    identical(block$type, "text")
  }, logical(1)))) {
    return(mcp_content_as_text(result$content))
  }

  if (length(content) == 1) {
    return(content[[1]])
  }

  content
}

mcp_abort_jsonrpc_error <- function(error, call = caller_env()) {
  code <- error$code %||% NA
  message <- error$message %||% "MCP JSON-RPC request failed."

  cli::cli_abort(
    c(
      "MCP JSON-RPC request failed.",
      i = "Code: {.val {code}}.",
      i = "Message: {message}."
    ),
    class = "mcptools_jsonrpc_error",
    jsonrpc_error = error,
    call = call
  )
}

mcp_content_as_ellmer <- function(content) {
  switch(
    content$type,
    text = ellmer::ContentText(text = content$text %||% ""),
    image = ellmer::ContentImageInline(
      type = content$mimeType %||% "image/png",
      data = content$data
    ),
    mcp_content_as_json_text(content)
  )
}

mcp_content_as_json_text <- function(content) {
  ellmer::ContentText(text = to_json(content))
}

mcp_content_as_text <- function(content) {
  if (is.null(content)) {
    return("")
  }

  text <- vapply(content, function(block) {
    if (identical(block$type, "text")) {
      return(block$text %||% "")
    }

    to_json(block)
  }, character(1))

  paste(text, collapse = "\n")
}

# retrieve and increment the current jsonrpc id from a server
jsonrpc_id <- function(server_name) {
  current_id <- the$mcp_servers[[server_name]]$id
  the$mcp_servers[[server_name]]$id <- current_id + 1
  current_id
}

# client protocol: logging -----------------------------------------------------
log_cat_client <- function(x, append = TRUE) {
  log_file <- mcptools_client_log()
  cat(x, "\n\n", sep = "", append = append, file = log_file)
}

mcp_log_json_message <- function(prefix, message) {
  log_cat_client(c(prefix, to_json(mcp_redact_secrets(message))))
}

mcp_log_json_text <- function(prefix, text) {
  parsed <- tryCatch(
    jsonlite::parse_json(text),
    error = function(err) NULL
  )

  if (is.null(parsed)) {
    log_cat_client(c(prefix, text))
    return(invisible(NULL))
  }

  mcp_log_json_message(prefix, parsed)
}

mcp_redact_secrets <- function(x) {
  if (!is.list(x)) {
    return(x)
  }

  nms <- names(x)
  if (is.null(nms)) {
    return(lapply(x, mcp_redact_secrets))
  }

  secret_fields <- mcp_secret_fields()
  for (i in seq_along(x)) {
    name <- tolower(nms[[i]])
    if (nzchar(name) && name %in% secret_fields) {
      x[[i]] <- "<redacted>"
    } else {
      x[[i]] <- mcp_redact_secrets(x[[i]])
    }
  }

  x
}

mcp_secret_fields <- function() {
  c(
    "authorization",
    "access_token",
    "refresh_token",
    "id_token",
    "client_secret",
    "secret",
    "password",
    "token"
  )
}

# client protocol: stdio --------------------------------------------------------
mcp_transport_stdio_send <- function(transport, message, expect_response = TRUE) {
  json_msg <- jsonlite::toJSON(message, auto_unbox = TRUE)
  mcp_log_json_message("FROM CLIENT: ", message)
  transport$process$write_input(paste0(json_msg, "\n"))

  if (!expect_response) {
    return(invisible(NULL))
  }

  # poll for response
  output <- NULL
  attempts <- 0
  max_attempts <- 20

  while (length(output) == 0 && attempts < max_attempts) {
    Sys.sleep(0.2)
    output <- transport$process$read_output_lines()
    attempts <- attempts + 1
  }

  if (!is.null(output) && length(output) > 0) {
    mcp_log_json_text("FROM SERVER: ", output[1])
    return(jsonlite::parse_json(output[1]))
  }

  log_cat_client(c("ALERT: No response received after ", attempts, " attempts"))
  return(NULL)
}

mcp_transport_stdio_close <- function(transport) {
  process <- transport$process
  if (is.null(process)) {
    return(invisible(FALSE))
  }

  if (isTRUE(process$is_alive())) {
    process$kill()
  }

  the$server_processes <- the$server_processes[!vapply(
    the$server_processes,
    identical,
    logical(1),
    process
  )]

  invisible(TRUE)
}

# protocol messages ------------------------------------------------------------
# step 1: initialize the MCP connection
mcp_request_initialize <- function(id = 1L) {
  list(
    jsonrpc = "2.0",
    id = id,
    method = "initialize",
    params = list(
      protocolVersion = latest_protocol_version,
      capabilities = named_list(),
      clientInfo = list(
        name = "mcptools",
        version = as.character(utils::packageVersion("mcptools"))
      )
    )
  )
}

# step 2: send initialized notification
mcp_request_initialized <- function() {
  list(
    jsonrpc = "2.0",
    method = "notifications/initialized"
  )
}

# step 3: request the list of tools
mcp_request_tools_list <- function(id = 2L, cursor = NULL) {
  request <- list(
    jsonrpc = "2.0",
    id = id,
    method = "tools/list"
  )

  if (!is.null(cursor)) {
    request$params <- list(cursor = cursor)
  }

  request
}

# step 4: call tools
mcp_request_tool_call <- function(id, tool, arguments) {
  if (length(arguments) == 0) {
    params <- list(name = tool)
  } else {
    params <- list(name = tool, arguments = arguments)
  }

  list(
    jsonrpc = "2.0",
    id = id,
    method = "tools/call",
    params = params
  )
}

mcp_request_cancelled <- function(request_id, reason = NULL) {
  params <- list(requestId = request_id)
  if (!is.null(reason)) {
    params$reason <- reason
  }

  list(
    jsonrpc = "2.0",
    method = "notifications/cancelled",
    params = params
  )
}
