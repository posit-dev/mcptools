skip_if(is_fedora())

test_that("mcp_tools works", {
  skip_if_not_installed("withr")
  skip_if(identical(Sys.getenv("GITHUB_PAT"), ""))
  skip_on_os(c("windows", "mac"))
  skip_if(
    identical(unname(Sys.which("docker")), ""),
    message = "Docker is not installed."
  )

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
  withr::local_options(.mcptools_config = tmp_file)

  res <- mcp_tools()
  expect_type(res, "list")
  expect_true(all(vapply(res, inherits, logical(1), "ellmer::ToolDef")))

  skip_if(identical(Sys.getenv("ANTHROPIC_API_KEY"), ""))
  ch <- ellmer::chat_openai("Be terse", model = "gpt-4.1-mini-2025-04-14")
  ch$set_tools(res)
  ch$chat("How many issues are there open on posit-dev/mcptools?")
  turns <- ch$get_turns()
  last_user_turn <- turns[[length(turns) - 1]]
  expect_true(inherits(
    last_user_turn@contents[[1]],
    "ellmer::ContentToolResult"
  ))
  expect_null(last_user_turn@contents[[1]]@error)
})

test_that("mcp_client_config() uses option when available", {
  withr::local_options(.mcptools_config = "/option/path")
  expect_equal(mcp_client_config(), "/option/path")
})

test_that("mcp_client_config() uses default when no option set", {
  withr::local_options(.mcptools_config = NULL)
  expect_equal(mcp_client_config(), default_mcp_client_config())
})

test_that("mcp_tools() errors informatively when file doesn't exist", {
  expect_snapshot(mcp_tools("nonexistent/file/"), error = TRUE)
})

test_that("mcp_tools() errors informatively with invalid JSON", {
  tmp_file <- withr::local_tempfile()
  writeLines("invalid json", tmp_file)
  expect_snapshot(mcp_tools(tmp_file), error = TRUE)
})

test_that("mcp_tools() errors informatively without mcpServers entry", {
  tmp_file <- withr::local_tempfile()
  config <- list(otherField = "value")
  writeLines(jsonlite::toJSON(config), tmp_file)
  expect_snapshot(mcp_tools(tmp_file), error = TRUE)
})

test_that("mcp_tools() returns mcpServers when valid", {
  tmp_file <- withr::local_tempfile()
  config <- list(
    mcpServers = list(
      server1 = list(command = "test", args = c("arg1"))
    )
  )
  writeLines(jsonlite::toJSON(config), tmp_file)
  result <- read_mcp_config(tmp_file)
  expect_equal(result, config$mcpServers)
})

test_that("mcp_tool_result_as_ellmer handles text content", {
  response <- list(
    result = list(
      content = list(list(type = "text", text = "hello")),
      isError = FALSE
    )
  )

  expect_equal(mcp_tool_result_as_ellmer(response), "hello")
})

test_that("mcp_tool_result_as_ellmer handles image content", {
  response <- list(
    result = list(
      content = list(list(
        type = "image",
        data = "abc123",
        mimeType = "image/png"
      )),
      isError = FALSE
    )
  )

  result <- mcp_tool_result_as_ellmer(response)

  expect_s3_class(result, "ellmer::ContentImageInline")
  expect_equal(result@data, "abc123")
  expect_equal(result@type, "image/png")
})

test_that("mcp_tool_result_as_ellmer handles mixed content", {
  response <- list(
    result = list(
      content = list(
        list(type = "text", text = "caption"),
        list(type = "image", data = "abc123", mimeType = "image/png")
      ),
      isError = FALSE
    )
  )

  result <- mcp_tool_result_as_ellmer(response)

  expect_length(result, 2)
  expect_s3_class(result[[1]], "ellmer::ContentText")
  expect_s3_class(result[[2]], "ellmer::ContentImageInline")
})

test_that("mixed MCP content expands in ellmer tool result turns", {
  response <- list(
    result = list(
      content = list(
        list(type = "text", text = "caption"),
        list(type = "image", data = "abc123", mimeType = "image/png")
      ),
      isError = FALSE
    )
  )
  request <- ellmer::ContentToolRequest(
    id = "call_1",
    name = "get_reference_image",
    arguments = list()
  )

  result <- ellmer:::new_tool_result(request, mcp_tool_result_as_ellmer(response))
  turn <- ellmer:::user_turn(result)
  turn <- ellmer:::turn_contents_expand(turn)

  expect_s3_class(turn@contents[[1]], "ellmer::ContentToolResult")
  expect_s3_class(turn@contents[[2]], "ellmer::ContentText")
  expect_s3_class(turn@contents[[3]], "ellmer::ContentText")
  expect_s3_class(turn@contents[[4]], "ellmer::ContentText")
  expect_equal(turn@contents[[4]]@text, "caption")
  expect_s3_class(turn@contents[[7]], "ellmer::ContentImageInline")
  expect_s3_class(turn@contents[[9]], "ellmer::ContentText")
})

test_that("MCP image content serializes as image content in ellmer", {
  response <- list(
    result = list(
      content = list(list(
        type = "image",
        data = "abc123",
        mimeType = "image/png"
      )),
      isError = FALSE
    )
  )
  request <- ellmer::ContentToolRequest(
    id = "call_1",
    name = "get_reference_image",
    arguments = list()
  )

  result <- ellmer:::new_tool_result(request, mcp_tool_result_as_ellmer(response))
  turn <- ellmer:::user_turn(result)
  provider <- ellmer::chat_openai(model = "gpt-4.1-mini-2025-04-14")$get_provider()
  json <- ellmer:::as_json(provider, turn)
  json <- to_json(json)

  expect_match(json, "input_image", fixed = TRUE)
  expect_match(json, "data:image/png;base64,abc123", fixed = TRUE)
})

test_that("OpenAI can inspect an MCP image tool result", {
  skip_on_cran()
  skip_if(identical(Sys.getenv("OPENAI_API_KEY"), ""))

  image_path <- tempfile(pattern = "reference-image-", fileext = ".jpg")
  stopifnot(!grepl("cat", basename(image_path), ignore.case = TRUE))
  download.file(
    "https://upload.wikimedia.org/wikipedia/commons/3/3a/Cat03.jpg",
    image_path,
    mode = "wb",
    quiet = TRUE
  )

  tool_file <- withr::local_tempfile(fileext = ".R")
  writeLines(
    c(
      "list(",
      "  get_reference_image = ellmer::tool(",
      sprintf(
        "    fun = function() ellmer::content_image_file(%s),",
        shQuote(image_path)
      ),
      "    name = 'get_reference_image',",
      "    description = 'Return the reference image as inline image content.',",
      "    arguments = list()",
      "  )",
      ")"
    ),
    tool_file
  )

  server_expr <- sprintf(
    "pkgload::load_all('.', quiet = TRUE); mcptools::mcp_server(tools = %s, session_tools = FALSE)",
    shQuote(tool_file)
  )
  config_file <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(
    list(
      mcpServers = list(
        image_demo = list(
          command = rscript_binary(),
          args = c("-e", server_expr)
        )
      )
    ),
    config_file,
    auto_unbox = TRUE
  )

  tools <- mcp_tools(config_file)
  server_process <- tail(the$server_processes, 1)[[1]]
  withr::defer(server_process$kill())

  chat <- ellmer::chat_openai(model = "gpt-4.1-mini-2025-04-14", echo = "none")
  chat$set_tools(tools)
  reply <- chat$chat(
    "Call the get_reference_image tool, inspect the image it returns, and name the animal shown.",
    echo = "none"
  )

  expect_true(grepl("cat", reply, ignore.case = TRUE))
})

test_that("mcp_tool_result_as_ellmer handles tool errors", {
  response <- list(
    result = list(
      content = list(list(type = "text", text = "bad input")),
      isError = TRUE
    )
  )

  result <- mcp_tool_result_as_ellmer(response)

  expect_s3_class(result, "ellmer::ContentToolResult")
  expect_equal(result@error, "bad input")
})

test_that("mcp_tools() errors informatively when process exits", {
  skip_on_cran()
  skip_on_ci()

  config <- list(
    mcpServers = list(
      "test" = list(
        command = "Rscript",
        args = c("-e", "stop('intentional error')")
      )
    )
  )

  tmpfile <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(config, tmpfile, auto_unbox = TRUE)

  expect_snapshot(error = TRUE, mcp_tools(tmpfile))
})
