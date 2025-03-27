test_that("mcp_config produces correct Claude Code output", {
  expect_snapshot(mcp_config("Claude Code"))
})

test_that("mcp_config produces correct Claude Desktop output for macOS", {
  local_mocked_bindings(
    is_linux = function() FALSE,
    is_windows = function() FALSE
  )
  expect_snapshot(mcp_config("Claude Desktop"))
})

test_that("mcp_config produces correct Claude Desktop output for Windows", {
  local_mocked_bindings(
    is_linux = function() FALSE,
    is_windows = function() TRUE
  )
  expect_snapshot(mcp_config("Claude Desktop"))
})

test_that("mcp_config errors correctly for Linux with Claude Desktop", {
  local_mocked_bindings(
    is_linux = function() TRUE
  )
  expect_snapshot(mcp_config("Claude Desktop"), error = TRUE)
})
