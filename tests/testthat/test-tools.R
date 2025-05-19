test_that("mcp_set_tools works", {
  old_option <- getOption("acquaint_tools")
  on.exit(options(.acquaint_tools = old_option))

  # must be a list
  expect_snapshot(error = TRUE, mcp_set_tools("boop"))

  tool_rnorm <- ellmer::tool(
    rnorm,
    "Draw numbers from a random normal distribution",
    n = ellmer::type_integer(
      "The number of observations. Must be a positive integer."
    ),
    mean = ellmer::type_number("The mean value of the distribution."),
    sd = ellmer::type_number(
      "The standard deviation of the distribution. Must be a non-negative number."
    )
  )
  tool_rnorm_list <- list(tool_rnorm)

  # tools themselves need to be in a list
  expect_snapshot(error = TRUE, mcp_set_tools(tool_rnorm))

  # uses reserved name
  tool_rnorm@name <- "list_r_sessions"
  expect_snapshot(error = TRUE, mcp_set_tools(list(tool_rnorm)))

  expect_equal(mcp_set_tools(tool_rnorm_list), tool_rnorm_list)
  expect_equal(
    names(get_acquaint_tools()),
    c("rnorm", "list_r_sessions", "select_r_session")
  )
})
