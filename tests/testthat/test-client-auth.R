skip_if(is_fedora())

# OAuth: helpers ---------------------------------------------------------------
test_that("mcp_resp_www_authenticate parses Bearer challenge parameters", {
  resp <- httr2::response(
    status_code = 401L,
    headers = list(
      "WWW-Authenticate" = 'Bearer resource_metadata="https://example.test/.well-known/oauth-protected-resource", scope="read write"'
    )
  )

  challenge <- mcp_resp_www_authenticate(resp)
  expect_equal(
    challenge$resource_metadata,
    "https://example.test/.well-known/oauth-protected-resource"
  )
  expect_equal(challenge$scope, "read write")
})

test_that("authorization server selection errors on ambiguity without override", {
  expect_error(
    mcp_select_authorization_server(
      list(authorization_servers = list("https://a.test", "https://b.test"))
    ),
    "multiple OAuth authorization servers"
  )

  expect_equal(
    mcp_select_authorization_server(
      list(authorization_servers = list("https://a.test", "https://b.test")),
      override = "https://a.test"
    ),
    "https://a.test"
  )

  expect_error(
    mcp_select_authorization_server(
      list(authorization_servers = list("https://a.test")),
      override = "https://other.test"
    ),
    "not advertised"
  )
})

test_that("authorization server metadata tries OAuth before OpenID", {
  types <- character()
  local_mocked_bindings(
    oauth_server_metadata = function(issuer, type) {
      types <<- c(types, type)
      if (identical(type, "oauth")) {
        cli::cli_abort("no oauth-authorization-server document")
      }
      list(issuer = issuer)
    },
    .package = "httr2"
  )

  metadata <- mcp_oauth_server_metadata("https://auth.test")
  expect_equal(metadata$issuer, "https://auth.test")
  expect_equal(types, c("oauth", "openid"))
})

test_that("authorization server metadata prefers the OAuth document", {
  types <- character()
  local_mocked_bindings(
    oauth_server_metadata = function(issuer, type) {
      types <<- c(types, type)
      list(issuer = issuer, type = type)
    },
    .package = "httr2"
  )

  metadata <- mcp_oauth_server_metadata("https://auth.test")
  expect_equal(metadata$type, "oauth")
  expect_equal(types, "oauth")
})

test_that("PKCE S256 support is required", {
  expect_silent(
    mcp_validate_oauth_pkce(list(code_challenge_methods_supported = list("S256")))
  )
  expect_error(
    mcp_validate_oauth_pkce(list(code_challenge_methods_supported = list("plain"))),
    "PKCE S256"
  )
})

test_that("OAuth scope precedence follows MCP defaults", {
  expect_equal(
    mcp_oauth_scope(
      oauth = list(scope = "configured", scope_mode = "override"),
      challenge = list(scope = "challenge"),
      prm = list(scopes_supported = list("prm"))
    ),
    "configured"
  )
  expect_equal(
    mcp_oauth_scope(
      challenge = list(scope = "challenge"),
      prm = list(scopes_supported = list("prm"))
    ),
    "challenge"
  )
  expect_equal(
    mcp_oauth_scope(prm = list(scopes_supported = list("a", "b"))),
    "a b"
  )
  expect_null(mcp_oauth_scope())
})

test_that("OAuth client metadata uses defaults, custom metadata, and scope", {
  metadata <- mcp_oauth_client_metadata(
    list(callback_port = 1410L, callback_host = "localhost", callback_path = "/oauth/callback"),
    scope = "read"
  )
  expect_equal(metadata$token_endpoint_auth_method, "none")
  expect_equal(metadata$redirect_uris[[1]], "http://localhost:1410/oauth/callback")
  expect_equal(metadata$scope, "read")

  metadata <- mcp_oauth_client_metadata(
    list(
      callback_port = 1410L,
      client_metadata = list(client_name = "custom", token_endpoint_auth_method = "client_secret_basic")
    )
  )
  expect_equal(metadata$client_name, "custom")
  expect_equal(metadata$token_endpoint_auth_method, "client_secret_basic")
})

test_that("OAuth authorization server endpoints must use HTTPS", {
  https <- list(
    authorization_endpoint = "https://auth.test/authorize",
    token_endpoint = "https://auth.test/token",
    registration_endpoint = "https://auth.test/register"
  )
  expect_silent(mcp_validate_oauth_metadata_endpoints(https))

  # a missing optional endpoint is not validated
  expect_silent(mcp_validate_oauth_metadata_endpoints(https["token_endpoint"]))

  expect_error(
    mcp_validate_oauth_metadata_endpoints(list(
      authorization_endpoint = "http://auth.test/authorize",
      token_endpoint = "https://auth.test/token"
    )),
    "must use HTTPS"
  )

  expect_silent(mcp_validate_oauth_metadata_endpoints(list(
    authorization_endpoint = "http://127.0.0.1:8080/authorize",
    token_endpoint = "http://localhost:8080/token"
  )))

  expect_silent(mcp_validate_oauth_metadata_endpoints(
    list(token_endpoint = "http://auth.test/token"),
    allow_http = TRUE
  ))

  expect_error(
    mcp_validate_oauth_metadata_endpoints(list(token_endpoint = "not-a-url")),
    "not a valid URL"
  )
})

test_that("OAuth redirect URIs must use HTTPS or local HTTP", {
  expect_silent(mcp_validate_oauth_redirect_uri("https://example.test/callback"))
  expect_silent(mcp_validate_oauth_redirect_uri("http://localhost:1410/oauth/callback"))
  expect_error(
    mcp_validate_oauth_redirect_uri("http://example.test/callback"),
    "must use HTTPS or HTTP on localhost"
  )
})

test_that("OAuth scope config requires explicit override mode", {
  expect_error(
    mcp_config_oauth(list(oauth = list(scope = "read"))),
    "scope_mode"
  )
  oauth <- mcp_config_oauth(list(oauth = list(scope = "read", scope_mode = "override")))
  expect_equal(oauth$scope, "read")
})

test_that("OAuth config supports environment interpolation", {
  withr::local_envvar(MCPTOOLS_TEST_CLIENT = "client-from-env")
  oauth <- mcp_config_oauth(list(oauth = list(
    client_info = list(client_id = "${MCPTOOLS_TEST_CLIENT}")
  )))
  expect_equal(oauth$client_info$client_id, "client-from-env")
})

# OAuth: cache -----------------------------------------------------------------
test_that("OAuth client-registration cache writes restricted JSON", {
  cache_dir <- withr::local_tempdir()
  oauth <- list(cache_dir = cache_dir)

  mcp_oauth_cache_write(oauth, "key-1", "client_registration", list(client_id = "id"))
  expect_equal(
    mcp_oauth_cache_read(oauth, "key-1", "client_registration")$client_id,
    "id"
  )
  expect_null(mcp_oauth_cache_read(oauth, "key-2", "client_registration"))

  if (.Platform$OS.type != "windows") {
    path <- mcp_oauth_cache_path(oauth, "key-1", "client_registration")
    expect_match(format(file.mode(path)), "600")
  }
})

test_that("OAuth cache key is stable for a server identity and varies by client", {
  transport <- mcp_transport_http(list(
    url = "https://example.test/mcp",
    oauth = list(authorization_server = "https://auth.test")
  ))
  transport$oauth_client_info <- list(client_id = "client-a")
  key_a <- mcp_oauth_cache_key(transport)

  transport$oauth_client_info <- list(client_id = "client-b")
  key_b <- mcp_oauth_cache_key(transport)

  expect_type(key_a, "character")
  expect_false(identical(key_a, key_b))
})

# OAuth: orchestration ---------------------------------------------------------
test_that("HTTP requests attach cached OAuth bearer tokens", {
  transport <- mcp_transport_http(list(
    url = "https://example.test/mcp",
    oauth = list(client_info = list(client_id = "id"))
  ))
  transport$oauth_token <- list(access_token = "cached-token")

  req <- mcp_transport_http_request(transport, mcp_request_tools_list(id = 2L))
  headers <- httr2::req_get_headers(req, "reveal")
  expect_equal(headers$Authorization, "Bearer cached-token")
})

test_that("a 401 challenge discovers and establishes an OAuth client", {
  transport <- mcp_transport_http(list(
    url = "https://example.test/mcp",
    oauth = list(authorization_server = "https://auth.test")
  ))

  metadata <- list(
    issuer = "https://auth.test",
    authorization_endpoint = "https://auth.test/authorize",
    token_endpoint = "https://auth.test/token",
    code_challenge_methods_supported = list("S256")
  )

  local_mocked_bindings(
    mcp_oauth_discover = function(...) metadata,
    mcp_oauth_client_info = function(...) list(client_id = "registered-client"),
    mcp_oauth_prepare_token = function(transport, ...) {
      transport$oauth_token <- list(access_token = "tok")
    }
  )

  expect_true(mcp_oauth_authorize_from_challenge(
    transport,
    httr2::response(status_code = 401L)
  ))
  expect_s3_class(transport$oauth_client, "httr2_oauth_client")
  expect_equal(transport$oauth_client$id, "registered-client")
  expect_equal(transport$oauth_auth_url, "https://auth.test/authorize")
  expect_type(transport$oauth_cache_key, "character")
  expect_equal(transport$oauth_token$access_token, "tok")
})

test_that("mcp_oauth_prepare_token delegates the token lifecycle to httr2", {
  transport <- mcp_transport_http(list(
    url = "https://example.test/mcp",
    oauth = list(authorization_server = "https://auth.test")
  ))
  transport$oauth_client <- httr2::oauth_client(id = "c", token_url = "https://auth.test/token")
  transport$oauth_auth_url <- "https://auth.test/authorize"
  transport$oauth_cache_key <- "cache-key"

  args <- NULL
  local_mocked_bindings(
    oauth_token_cached = function(...) {
      args <<- list(...)
      list(access_token = "abc")
    },
    .package = "httr2"
  )

  token <- mcp_oauth_prepare_token(transport)
  expect_equal(token$access_token, "abc")
  expect_equal(transport$oauth_token$access_token, "abc")
  expect_true(args$cache_disk)
  expect_equal(args$cache_key, "cache-key")
})

test_that("dynamic client registration caches the registered client", {
  cache_dir <- withr::local_tempdir()
  transport <- mcp_transport_http(list(
    url = "https://example.test/mcp",
    oauth = list(authorization_server = "https://auth.test", cache_dir = cache_dir)
  ))
  metadata <- list(
    issuer = "https://auth.test",
    registration_endpoint = "https://auth.test/register"
  )

  register_calls <- 0L
  local_mocked_bindings(
    mcp_oauth_register_client = function(...) {
      register_calls <<- register_calls + 1L
      list(client_id = "dcr-client")
    }
  )

  info <- mcp_oauth_client_info(transport, metadata, scope = NULL)
  expect_equal(info$client_id, "dcr-client")
  expect_equal(register_calls, 1L)

  # second resolution reads the cached registration
  info <- mcp_oauth_client_info(transport, metadata, scope = NULL)
  expect_equal(info$client_id, "dcr-client")
  expect_equal(register_calls, 1L)
})

test_that("mcp_transport_http_send retries once after a 401 and succeeds", {
  transport <- mcp_transport_http(list(
    url = "https://example.test/mcp",
    oauth = list(authorization_server = "https://auth.test")
  ))

  local_mocked_bindings(
    mcp_oauth_authorize_from_challenge = function(transport, ...) {
      transport$oauth_token <- list(access_token = "tok")
      TRUE
    }
  )

  calls <- 0L
  httr2::local_mocked_responses(function(req) {
    calls <<- calls + 1L
    if (calls == 1L) {
      return(httr2::response(status_code = 401L, url = req$url, method = req$method))
    }
    expect_equal(httr2::req_get_headers(req, "reveal")$Authorization, "Bearer tok")
    httr2::response(
      status_code = 200L,
      url = req$url,
      method = req$method,
      headers = list("Content-Type" = "application/json"),
      body = charToRaw(to_json(jsonrpc_response(req$body$data$id, result = named_list())))
    )
  })

  response <- mcp_transport_request(transport, mcp_request_tools_list(id = 2L))
  expect_equal(calls, 2L)
  expect_false(is.null(response$result))
})

test_that("an unrecoverable 401 raises an auth-required condition", {
  transport <- mcp_transport_http(list(url = "https://example.test/mcp"))

  httr2::local_mocked_responses(function(req) {
    httr2::response(
      status_code = 401L,
      url = req$url,
      method = req$method,
      headers = list("WWW-Authenticate" = 'Bearer error="invalid_token"')
    )
  })

  expect_error(
    mcp_transport_request(transport, mcp_request_tools_list(id = 2L)),
    class = "mcptools_http_auth_required"
  )
})
