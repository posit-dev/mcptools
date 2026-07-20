skip_if(is_fedora())

test_that("jsonrpc_response works", {
  # jsonrpc_response returns result when provided
  result <- jsonrpc_response("123", result = "success")
  expect_equal(result$jsonrpc, "2.0")
  expect_equal(result$id, "123")
  expect_equal(result$result, "success")
  expect_null(result$error)

  # jsonrpc_response returns error when provided
  result <- jsonrpc_response(
    "456",
    error = list(code = -32603, message = "Internal error")
  )
  expect_equal(result$jsonrpc, "2.0")
  expect_equal(result$id, "456")
  expect_null(result$result)
  expect_equal(result$error, list(code = -32603, message = "Internal error"))

  # jsonrpc_response warns when both result and error provided
  expect_snapshot(
    .res <- jsonrpc_response(
      "789",
      result = "success",
      error = list(code = -32603, message = "error")
    )
  )

  # jsonrpc_response warns when neither result nor error provided
  expect_snapshot(.res <- jsonrpc_response("000"))
})

test_that("named_list works", {
  # named_list creates named list with arguments
  result <- named_list(a = 1, b = 2)
  expect_equal(result, list(a = 1, b = 2))
  expect_true(is.list(result))
  expect_equal(names(result), c("a", "b"))

  # named_list creates empty named list when no arguments
  result <- named_list()
  expect_equal(result, list(a = 1)[0])
  expect_true(is.list(result))
  expect_equal(length(result), 0)
  expect_true(!is.null(names(result)))
})

test_that("to_json works", {
  # to_json converts list to JSON with auto_unbox
  result <- to_json(list(a = 1, b = "text"))
  expect_true(is.character(result))
  expect_equal(jsonlite::fromJSON(result), list(a = 1, b = "text"))

  # to_json passes additional arguments to jsonlite::toJSON
  result <- to_json(list(a = 1), pretty = TRUE)
  expect_true(grepl("\n", result))

  # to_json handles single values with auto_unbox
  result <- to_json(list(value = 42))
  parsed <- jsonlite::fromJSON(result)
  expect_equal(parsed$value, 42)
  expect_false(is.list(parsed$value))
})

test_that("to_json serializes null values as JSON null", {
  response <- jsonrpc_response(
    NULL,
    error = list(code = -32600, message = "Invalid Request")
  )

  result <- to_json(response)

  expect_match(result, '"id":null', fixed = TRUE)
  expect_false(grepl('"id":{}', result, fixed = TRUE))

  expect_equal(as.character(to_json(list(value = NULL))), '{"value":null}')
})

test_that("url_origin handles full URLs and invalid input", {
  expect_equal(
    url_origin("https://connect.example.com/rsc/content/123"),
    "https://connect.example.com"
  )
  expect_equal(
    url_origin("https://connect.example.com:3939/rsc/content/123"),
    "https://connect.example.com:3939"
  )
  expect_null(url_origin("not a url"))
})

test_that("constant_time_equal compares strings", {
  expect_true(constant_time_equal("secret", "secret"))
  expect_false(constant_time_equal("secret", "wrong"))
  expect_false(constant_time_equal("secret", "secret2"))
  expect_false(constant_time_equal("secret", NA_character_))
})

test_that("is_private_host_literal flags loopback, private, and link-local hosts", {
  private <- c(
    "localhost",
    "app.localhost",
    "127.0.0.1",
    "127.1.2.3",
    "0.0.0.0",
    "10.0.0.5",
    "172.16.0.1",
    "172.31.255.255",
    "192.168.1.1",
    "169.254.169.254",
    "::1",
    "fe80::1",
    "fc00::1",
    "fd12:3456::1",
    "::ffff:127.0.0.1",
    "::ffff:7f00:1", # IPv4-mapped loopback, hex hextet form
    "::ffff:a9fe:a9fe", # IPv4-mapped 169.254.169.254, hex hextet form
    "::ffff:169.254.169.254",
    "::ffff:10.0.0.1",
    "[::ffff:a9fe:a9fe]",
    "fe80::1%eth0",
    "::"
  )
  for (host in private) {
    expect_true(is_private_host_literal(host), info = host)
  }

  public <- c(
    "example.com",
    "8.8.8.8",
    "172.32.0.1",
    "172.15.0.1",
    "192.169.0.1",
    "2001:db8::1",
    "2606:4700:4700::1111",
    "::ffff:8.8.8.8",
    "::ffff:808:808", # IPv4-mapped 8.8.8.8, hex hextet form
    "127.evil.example.com"
  )
  for (host in public) {
    expect_false(is_private_host_literal(host), info = host)
  }
})

test_that("is_loopback_host_literal flags only genuine loopback literals", {
  loopback <- c(
    "localhost",
    "app.localhost",
    "127.0.0.1",
    "127.1.2.3",
    "::1",
    "[::1]",
    "0:0:0:0:0:0:0:1",
    "::ffff:127.0.0.1",
    "::ffff:7f00:1"
  )
  for (host in loopback) {
    expect_true(is_loopback_host_literal(host), info = host)
  }

  not_loopback <- c(
    "127.evil.example.com",
    "10.0.0.5",
    "169.254.169.254",
    "example.com",
    "fe80::1",
    "::ffff:a9fe:a9fe",
    "2606:4700:4700::1111"
  )
  for (host in not_loopback) {
    expect_false(is_loopback_host_literal(host), info = host)
  }
})

test_that("mcptools_server_log works", {
  # mcptools_server_log returns environment variable when set
  withr::local_envvar(MCPTOOLS_SERVER_LOG = "/custom/log/file.txt")
  result <- mcptools_server_log()
  expect_equal(result, "/custom/log/file.txt")

  # mcptools_server_log returns tempfile when environment variable not set
  withr::local_envvar(MCPTOOLS_SERVER_LOG = NULL)
  result <- mcptools_server_log()
  expect_true(grepl("\\.txt$", result))
  expect_true(file.exists(dirname(result)))
})
