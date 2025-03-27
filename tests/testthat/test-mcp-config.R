# TODO: just make the paths resilient to tempdirs, either by transforming
# the snapshot or mocking system.file
skip_on_ci()
skip_on_cran()
skip_if(nzchar(Sys.getenv("_R_CHECK_PACKAGE_NAME_", "")), "in R CMD check")

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
