test_that("mcp_tools works", {
  skip_if_not_installed("withr")
  skip_if(identical(Sys.getenv("GITHUB_PAT"), ""))
  skip_on_os(c("windows", "mac"))

  tmp_file <- withr::local_tempfile()

  # example configuration: official GitHub MCP server
  config <- list(
    mcpServers = list(
      github = list(
        command = "docker",
        args = c(
          "run",
          "-i",
          "--rm",
          "-e",
          "GITHUB_PERSONAL_ACCESS_TOKEN",
          "ghcr.io/github/github-mcp-server"
        ),
        env = list(GITHUB_PERSONAL_ACCESS_TOKEN = Sys.getenv("GITHUB_PAT"))
      )
    )
  )
  writeLines(jsonlite::toJSON(config), tmp_file)
  withr::local_options(.acquaint_config = tmp_file)

  res <- mcp_tools()
  expect_type(res, "list")
  expect_true(all(vapply(res, inherits, logical(1), "ellmer::ToolDef")))

  skip_if(identical(Sys.getenv("ANTHROPIC_API_KEY"), ""))
  ch <- ellmer::chat_openai("Be terse", model = "gpt-4.1-mini-2025-04-14")
  ch$set_tools(res)
  ch$chat("How many issues are there open on posit-dev/acquaint?")
  turns <- ch$get_turns()
  last_user_turn <- turns[[length(turns) - 1]]
  expect_true(inherits(
    last_user_turn@contents[[1]],
    "ellmer::ContentToolResult"
  ))
  expect_null(last_user_turn@contents[[1]]@error)
})
