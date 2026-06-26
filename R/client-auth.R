# This file implements the client's OAuth 2.1 authorization flow.

# client protocol: OAuth -------------------------------------------------------
# OAuth runs the standard MCP authorization flow: a 401 challenge points to the
# protected-resource metadata, which names the authorization server. mcptools
# discovers that server's metadata (via httr2), establishes a client (static,
# manual, or Dynamic Client Registration), then runs the authorization-code
# flow with PKCE. Tokens and registered clients are cached on disk so they are
# reused across sessions and refreshed without re-prompting.

# Attach a cached, valid token to `transport$oauth_token` when one can be found
# without prompting; refresh it first if it has expired.
# Attach a valid bearer token to the transport once an OAuth client has been
# established. httr2's oauth_token_cached() owns the token lifecycle: it reads
# the on-disk cache, refreshes via the refresh token, or runs the browser flow
# as needed. `reauth` forces a fresh flow, bypassing a rejected cached token.
mcp_oauth_prepare_token <- function(transport, reauth = FALSE, call = caller_env()) {
  client <- transport$oauth_client
  if (is.null(client)) {
    return(invisible(NULL))
  }

  token <- httr2::oauth_token_cached(
    client = client,
    flow = httr2::oauth_flow_auth_code,
    flow_params = mcp_oauth_flow_params(transport),
    cache_disk = TRUE,
    cache_key = transport$oauth_cache_key,
    reauth = reauth
  )

  transport$oauth_token <- unclass(token)
  invisible(transport$oauth_token)
}

mcp_oauth_active <- function(transport) {
  length(transport$oauth) > 0 &&
    !any(tolower(names(transport$headers)) == "authorization")
}

# Discover the authorization server from a 401/403 challenge, establish an OAuth
# client (static, manual, or via Dynamic Client Registration), and obtain a
# token. Returns TRUE when the caller should retry the original request.
mcp_oauth_authorize_from_challenge <- function(transport, resp, reauth = FALSE, call = caller_env()) {
  if (!mcp_oauth_active(transport)) {
    return(FALSE)
  }

  if (is.null(transport$oauth_client)) {
    challenge <- mcp_resp_www_authenticate(resp)
    metadata <- mcp_oauth_discover(transport, challenge, call = call)
    if (is.null(metadata)) {
      return(FALSE)
    }

    scope <- mcp_oauth_scope(transport$oauth, challenge, transport$oauth_prm)
    client_info <- mcp_oauth_client_info(transport, metadata, scope, call = call)
    if (is.null(client_info$client_id)) {
      return(FALSE)
    }

    transport$oauth_metadata <- metadata
    transport$oauth_client_info <- client_info
    transport$oauth_scope <- scope
    transport$oauth_auth_url <- metadata$authorization_endpoint
    transport$oauth_client <- httr2::oauth_client(
      id = client_info$client_id,
      secret = client_info$client_secret %||% client_info$secret %||% NULL,
      token_url = metadata$token_endpoint
    )
    transport$oauth_cache_key <- mcp_oauth_cache_key(transport)
  }

  token <- mcp_oauth_prepare_token(transport, reauth = reauth, call = call)
  !is.null(token$access_token)
}

mcp_oauth_flow_params <- function(transport) {
  resource_params <- mcp_oauth_resource_params(transport)
  list(
    auth_url = transport$oauth_auth_url,
    scope = transport$oauth_scope,
    pkce = TRUE,
    auth_params = resource_params,
    token_params = resource_params,
    redirect_uri = mcp_oauth_redirect_uri(transport$oauth)
  )
}

mcp_resp_www_authenticate <- function(resp) {
  mcp_parse_www_authenticate(httr2::resp_header(resp, "www-authenticate"))
}

# A compact WWW-Authenticate parser: it pulls the `key=value` auth params we act
# on (`resource_metadata`, `scope`, `error`) out of the challenge. It does not
# implement the full RFC 7235 grammar (multiple challenges, commas inside quoted
# values); those edge cases are not needed for the MCP authorization flow.
mcp_parse_www_authenticate <- function(header) {
  header <- header[!is.na(header) & nzchar(header)]
  if (length(header) == 0) {
    return(named_list())
  }

  text <- sub(
    "^\\s*[!#$%&'*+.^_`|~0-9A-Za-z-]+\\s+",
    "",
    paste(header, collapse = ", ")
  )

  out <- named_list()
  for (pair in strsplit(text, ",", fixed = TRUE)[[1]]) {
    eq <- regexpr("=", pair, fixed = TRUE)
    if (eq < 1L) {
      next
    }

    key <- tolower(trimws(substr(pair, 1L, eq - 1L)))
    value <- gsub('^"|"$', "", trimws(substr(pair, eq + 1L, nchar(pair))))
    if (nzchar(key)) {
      out[[key]] <- value
    }
  }

  out
}

# Resolve and validate the authorization-server metadata for the transport,
# caching the protected-resource metadata on the transport for scope discovery.
mcp_oauth_discover <- function(transport, challenge = named_list(), call = caller_env()) {
  prm <- mcp_discover_protected_resource_metadata(
    transport$url,
    challenge,
    timeout = transport$timeout,
    call = call
  )
  transport$oauth_prm <- prm

  issuer <- mcp_select_authorization_server(
    prm,
    override = transport$oauth$authorization_server,
    call = call
  )
  if (is.null(issuer)) {
    return(NULL)
  }

  metadata <- mcp_oauth_server_metadata(issuer)
  if (is.null(metadata)) {
    cli::cli_abort(
      c(
        "OAuth authorization server metadata discovery failed.",
        i = "Issuer: {.url {issuer}}."
      ),
      call = call
    )
  }

  mcp_validate_oauth_pkce(metadata, call = call)
  mcp_validate_oauth_metadata_endpoints(
    metadata,
    allow_http = isTRUE(transport$allow_http),
    call = call
  )
  metadata
}

# The authorization, token, and registration endpoints carry authorization
# codes, tokens, and client credentials, so the spec requires them to use HTTPS.
# Loopback and the explicit `allow_http` opt-out are permitted for development,
# mirroring the MCP endpoint and redirect-URI checks.
mcp_validate_oauth_metadata_endpoints <- function(metadata, allow_http = FALSE, call = caller_env()) {
  endpoints <- c(
    "authorization_endpoint" = metadata$authorization_endpoint,
    "token_endpoint" = metadata$token_endpoint,
    "registration_endpoint" = metadata$registration_endpoint
  )

  for (field in names(endpoints)) {
    mcp_validate_oauth_endpoint(
      endpoints[[field]],
      field = field,
      allow_http = allow_http,
      call = call
    )
  }

  invisible(TRUE)
}

mcp_validate_oauth_endpoint <- function(url, field, allow_http = FALSE, call = caller_env()) {
  parsed <- url_parse_or_null(url)
  if (is.null(parsed) || is.null(parsed$scheme) || is.null(parsed$hostname)) {
    cli::cli_abort(
      c(
        "OAuth authorization server metadata is invalid.",
        i = "{.field {field}} is not a valid URL: {.url {url}}."
      ),
      call = call
    )
  }

  scheme <- tolower(parsed$scheme)
  host <- tolower(parsed$hostname)

  if (identical(scheme, "https")) {
    return(invisible(TRUE))
  }

  if (identical(scheme, "http") && (mcp_oauth_is_loopback_host(host) || isTRUE(allow_http))) {
    return(invisible(TRUE))
  }

  cli::cli_abort(
    c(
      "OAuth authorization server endpoints must use HTTPS.",
      i = "{.field {field}}: {.url {url}}."
    ),
    call = call
  )
}

# The MCP authorization spec requires trying OAuth 2.0 authorization-server
# metadata (RFC 8414) before OpenID Connect discovery; httr2 defaults to the
# OpenID endpoint, so OAuth-only servers fail unless we attempt both.
mcp_oauth_server_metadata <- function(issuer) {
  for (type in c("oauth", "openid")) {
    metadata <- tryCatch(
      httr2::oauth_server_metadata(issuer, type = type),
      error = function(err) NULL
    )
    if (!is.null(metadata)) {
      return(metadata)
    }
  }

  NULL
}

mcp_select_authorization_server <- function(metadata, override = NULL, call = caller_env()) {
  issuers <- unlist(metadata$authorization_servers %||% character(), use.names = FALSE)

  if (!is.null(override)) {
    if (length(issuers) > 0 && !override %in% issuers) {
      cli::cli_abort(
        c(
          "Configured OAuth authorization server is not advertised by the MCP protected resource.",
          i = "Configured issuer: {.url {override}}.",
          i = "Advertised issuers: {.url {issuers}}."
        ),
        call = call
      )
    }

    return(override)
  }

  if (length(issuers) == 0) {
    return(NULL)
  }

  if (length(issuers) > 1) {
    cli::cli_abort(
      c(
        "MCP protected resource advertises multiple OAuth authorization servers.",
        i = "Configure {.field oauth.authorization_server}.",
        i = "Advertised issuers: {.url {issuers}}."
      ),
      call = call
    )
  }

  issuers[[1]]
}

mcp_discover_protected_resource_metadata <- function(
  resource_url,
  challenge = named_list(),
  timeout = NULL,
  call = caller_env()
) {
  for (url in mcp_protected_resource_metadata_urls(resource_url, challenge)) {
    req <- mcp_metadata_get_request(url, timeout = timeout)
    resp <- tryCatch(httr2::req_perform(req), error = function(err) NULL)
    if (is.null(resp) || !identical(httr2::resp_status(resp), 200L)) {
      next
    }

    metadata <- tryCatch(
      httr2::resp_body_json(resp, simplifyVector = FALSE),
      error = function(err) NULL
    )
    if (!is.null(metadata)) {
      return(metadata)
    }
  }

  NULL
}

mcp_protected_resource_metadata_urls <- function(resource_url, challenge = named_list()) {
  parsed <- url_parse_or_null(resource_url)
  if (is.null(parsed)) {
    return(character())
  }

  origin <- url_origin(resource_url)
  path <- sub("/$", "", parsed$path %||% "")

  urls <- character()
  if (!is.null(challenge$resource_metadata)) {
    urls <- c(urls, challenge$resource_metadata)
  }
  if (nzchar(path) && !identical(path, "/")) {
    urls <- c(urls, paste0(origin, "/.well-known/oauth-protected-resource", path))
  }
  urls <- c(urls, paste0(origin, "/.well-known/oauth-protected-resource"))

  unique(urls)
}

mcp_oauth_client_info <- function(transport, metadata, scope, call = caller_env()) {
  oauth <- transport$oauth

  if (!is.null(oauth$client_info)) {
    return(oauth$client_info)
  }

  registration_endpoint <- metadata$registration_endpoint %||% NULL
  if (!is.null(registration_endpoint)) {
    key <- mcp_oauth_cache_key(transport, kind = "client")
    cached <- if (!is.null(key)) {
      mcp_oauth_cache_read(oauth, key, "client_registration")
    } else {
      NULL
    }
    if (!is.null(cached)) {
      return(cached)
    }

    client_info <- mcp_oauth_register_client(
      registration_endpoint,
      mcp_oauth_client_metadata(oauth, scope),
      timeout = transport$timeout,
      call = call
    )
    if (!is.null(client_info) && !is.null(key)) {
      mcp_oauth_cache_write(oauth, key, "client_registration", client_info)
    }
    return(client_info)
  }

  oauth$manual_client_info
}

mcp_oauth_register_client <- function(
  registration_endpoint,
  client_metadata,
  timeout = NULL,
  call = caller_env()
) {
  req <- mcp_dcr_post_request(
    registration_endpoint,
    client_metadata = client_metadata,
    timeout = timeout
  )
  resp <- httr2::req_perform(req)
  status <- httr2::resp_status(resp)

  if (!status %in% c(200L, 201L)) {
    cli::cli_abort(
      c(
        "OAuth dynamic client registration failed.",
        i = "Status: {.val {status}}."
      ),
      call = call
    )
  }

  httr2::resp_body_json(resp, simplifyVector = FALSE)
}

mcp_oauth_client_metadata <- function(oauth, scope = NULL) {
  metadata <- named_list(
    redirect_uris = list(mcp_oauth_redirect_uri(oauth)),
    token_endpoint_auth_method = "none",
    grant_types = list("authorization_code", "refresh_token"),
    response_types = list("code"),
    client_name = "mcptools",
    client_uri = "https://github.com/posit-dev/mcptools",
    software_id = "mcptools",
    software_version = as.character(utils::packageVersion("mcptools"))
  )

  metadata <- utils::modifyList(metadata, oauth$client_metadata %||% list())
  if (!is.null(scope) && nzchar(scope)) {
    metadata$scope <- scope
  }

  metadata
}

mcp_oauth_resource_params <- function(transport) {
  resource <- transport$oauth$resource %||% NULL
  if (is.null(resource)) {
    return(named_list())
  }

  named_list(resource = resource)
}

mcp_oauth_scope <- function(oauth = named_list(), challenge = named_list(), prm = NULL) {
  if (!is.null(oauth$scope) && identical(oauth$scope_mode, "override")) {
    return(oauth$scope)
  }

  if (!is.null(challenge$scope) && nzchar(challenge$scope)) {
    return(challenge$scope)
  }

  scopes <- prm$scopes_supported %||% NULL
  if (length(scopes) > 0) {
    return(paste(unlist(scopes, use.names = FALSE), collapse = " "))
  }

  NULL
}

mcp_validate_oauth_pkce <- function(metadata, call = caller_env()) {
  methods <- unlist(metadata$code_challenge_methods_supported %||% character(), use.names = FALSE)
  if ("S256" %in% methods) {
    return(invisible(TRUE))
  }

  supported <- if (length(methods) == 0) "not advertised" else methods
  cli::cli_abort(
    c(
      "OAuth authorization server does not advertise PKCE S256 support.",
      i = "Supported methods: {.val {supported}}."
    ),
    call = call
  )
}

mcp_oauth_redirect_uri <- function(oauth) {
  if (!is.null(oauth$redirect_uri)) {
    return(oauth$redirect_uri)
  }

  paste0(
    "http://",
    oauth$callback_host %||% "localhost",
    ":",
    oauth$callback_port %||% 1410L,
    oauth$callback_path %||% "/oauth/callback"
  )
}

mcp_validate_oauth_redirect_uri <- function(redirect_uri, call = caller_env()) {
  parsed <- url_parse_or_null(redirect_uri)
  if (is.null(parsed)) {
    cli::cli_abort(
      c(
        "MCP OAuth configuration failed.",
        i = "OAuth redirect URI is not a valid URL: {.url {redirect_uri}}."
      ),
      call = call
    )
  }

  scheme <- tolower(parsed$scheme %||% "")
  host <- tolower(parsed$hostname %||% "")

  if (identical(scheme, "https")) {
    return(invisible(TRUE))
  }

  if (identical(scheme, "http") && mcp_oauth_is_loopback_host(host)) {
    return(invisible(TRUE))
  }

  cli::cli_abort(
    c(
      "MCP OAuth configuration failed.",
      i = "OAuth redirect URI must use HTTPS or HTTP on localhost.",
      i = "Redirect URI: {.url {redirect_uri}}."
    ),
    call = call
  )
}

mcp_oauth_resource <- function(url, call = caller_env()) {
  parsed <- url_parse_or_null(url)
  if (is.null(parsed) || is.null(parsed$scheme) || is.null(parsed$hostname)) {
    cli::cli_abort(
      c(
        "MCP OAuth configuration failed.",
        i = "OAuth resource must be an absolute URI."
      ),
      call = call
    )
  }

  if (!is.null(parsed$fragment)) {
    cli::cli_abort(
      c(
        "MCP OAuth configuration failed.",
        i = "OAuth resource must not include a fragment.",
        i = "Resource: {.url {url}}."
      ),
      call = call
    )
  }

  parsed$scheme <- tolower(parsed$scheme)
  parsed$hostname <- tolower(parsed$hostname)
  httr2::url_build(parsed)
}

mcp_oauth_is_loopback_host <- function(host) {
  identical(host, "localhost") ||
    startsWith(host, "127.") ||
    identical(host, "::1") ||
    identical(host, "0:0:0:0:0:0:0:1")
}

mcp_abort_http_auth <- function(transport, resp, status, call = caller_env()) {
  challenge <- mcp_resp_www_authenticate(resp)
  details <- c(
    if (!is.null(challenge$error)) "OAuth error: {.val {challenge$error}}.",
    if (!is.null(challenge$error_description)) {
      "OAuth error description: {challenge$error_description}."
    },
    if (!is.null(challenge$scope)) "Scope: {.val {challenge$scope}}."
  )

  cli::cli_abort(
    c(
      "MCP HTTP authorization failed.",
      i = "Status: {.val {status}}.",
      i = details
    ),
    class = "mcptools_http_auth_required",
    status = status,
    www_authenticate = challenge,
    call = call
  )
}

# OAuth cache key: a stable hash of the (server, issuer, client, scope) tuple.
# It namespaces httr2's on-disk token cache and our Dynamic Client Registration
# cache so both are reused across transports for the same server.
mcp_oauth_cache_key <- function(transport, kind = "tokens") {
  oauth <- transport$oauth
  client_id <- transport$oauth_client_info$client_id %||%
    oauth$client_info$client_id %||%
    oauth$manual_client_info$client_id %||%
    NULL

  issuer <- transport$oauth_metadata$issuer %||%
    oauth$authorization_server %||%
    NULL

  identity <- list(
    server_url = transport$url,
    resource = oauth$resource,
    issuer = issuer,
    scope = oauth$scope %||% transport$oauth_scope,
    redirect_uri = mcp_oauth_redirect_uri(oauth)
  )

  if (identical(kind, "tokens")) {
    if (is.null(client_id)) {
      return(NULL)
    }
    identity$client_id <- client_id
  }

  rlang::hash(identity)
}

mcp_oauth_cache_path <- function(oauth, key, kind) {
  file.path(oauth$cache_dir, key, paste0(kind, ".json"))
}

mcp_oauth_cache_read <- function(oauth, key, kind) {
  path <- mcp_oauth_cache_path(oauth, key, kind)
  if (!file.exists(path)) {
    return(NULL)
  }

  jsonlite::parse_json(paste(readLines(path, warn = FALSE), collapse = "\n"))
}

mcp_oauth_cache_write <- function(oauth, key, kind, value) {
  path <- mcp_oauth_cache_path(oauth, key, kind)
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  Sys.chmod(oauth$cache_dir, mode = "0700")
  Sys.chmod(dirname(path), mode = "0700")
  writeLines(to_json(value), path)
  Sys.chmod(path, mode = "0600")
  invisible(path)
}
