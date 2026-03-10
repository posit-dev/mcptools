skip_if(is_fedora())

# -- negotiate_protocol_version ------------------------------------------------

test_that("negotiate_protocol_version returns client version when supported", {
  expect_equal(negotiate_protocol_version("2024-11-05"), "2024-11-05")
  expect_equal(negotiate_protocol_version("2025-03-26"), "2025-03-26")
  expect_equal(negotiate_protocol_version("2025-06-18"), "2025-06-18")
  expect_equal(negotiate_protocol_version("2025-11-25"), "2025-11-25")
})

test_that("negotiate_protocol_version returns latest for unsupported version", {
  expect_equal(
    negotiate_protocol_version("2099-01-01"),
    latest_protocol_version
  )
  expect_equal(
    negotiate_protocol_version("not-a-version"),
    latest_protocol_version
  )
})

# -- version comparison helpers ------------------------------------------------

test_that("protocol_version_gte works", {
  expect_true(protocol_version_gte("2025-06-18", "2025-03-26"))
  expect_true(protocol_version_gte("2025-06-18", "2025-06-18"))
  expect_false(protocol_version_gte("2024-11-05", "2025-03-26"))
})

test_that("protocol_version_lt works", {
  expect_true(protocol_version_lt("2024-11-05", "2025-03-26"))
  expect_false(protocol_version_lt("2025-06-18", "2025-06-18"))
  expect_false(protocol_version_lt("2025-11-25", "2025-03-26"))
})

# -- capabilities --------------------------------------------------------------

test_that("capabilities uses supplied protocol version", {
  res <- capabilities("2025-11-25")
  expect_equal(res$protocolVersion, "2025-11-25")

  res <- capabilities("2024-11-05")
  expect_equal(res$protocolVersion, "2024-11-05")
})

test_that("capabilities defaults to latest protocol version", {
  res <- capabilities()
  expect_equal(res$protocolVersion, latest_protocol_version)
})

test_that("capabilities includes instructions for versions >= 2025-03-26", {
  res <- capabilities("2025-03-26")
  expect_true(!is.null(res$instructions))

  res <- capabilities("2025-06-18")
  expect_true(!is.null(res$instructions))

  res <- capabilities("2025-11-25")
  expect_true(!is.null(res$instructions))
})

test_that("capabilities omits instructions for version 2024-11-05", {
  res <- capabilities("2024-11-05")
  expect_null(res$instructions)
})

test_that("capabilities always includes required fields", {
  for (version in supported_protocol_versions) {
    res <- capabilities(version)
    expect_true(!is.null(res$protocolVersion))
    expect_true(!is.null(res$capabilities))
    expect_true(!is.null(res$serverInfo))
    expect_true(!is.null(res$capabilities$tools))
    expect_equal(res$serverInfo$name, "R mcptools server")
  }
})
