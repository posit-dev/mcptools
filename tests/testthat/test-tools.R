skip_if(is_fedora())

test_that("set_server_tools sets default tools when x is NULL", {
  set_server_tools(NULL)
  server_tools_names <- vapply(
    the$server_tools,
    function(x) x@name,
    character(1)
  )
  expect_true(all(
    c("list_r_sessions", "select_r_session") %in% server_tools_names
  ))
  expect_equal(length(the$server_tools), 2)
})

test_that("set_server_tools can handle `tools` as path", {
  tmp_file <- withr::local_tempfile(fileext = ".r")
  local_mocked_bindings(check_not_interactive = function(...) {})

  # temp file doesn't yet exist
  expect_snapshot(error = TRUE, mcp_server(tmp_file))

  # temp file errors when sourced
  writeLines("boop", tmp_file)
  expect_snapshot(error = TRUE, mcp_server(tmp_file))

  # temp file doesn't return a list of tools
  writeLines("\"boop\"", tmp_file)
  expect_snapshot(error = TRUE, mcp_server(tmp_file))

  expect_no_condition(
    set_server_tools(system.file(
      "example-ellmer-tools.R",
      package = "mcptools"
    ))
  )
  expect_true("tool_rnorm" %in% names(the$server_tools))
})

test_that("set_server_tools errors informatively", {
  tls <-
    source(
      system.file(
        "example-ellmer-tools.R",
        package = "mcptools"
      ),
      local = TRUE
    )

  # input must be a ToolDef or list of ToolDefs
  expect_snapshot(set_server_tools(123), error = TRUE)

  # check can accept a single ToolDef
  expect_no_error(set_server_tools(tls$value[[1]]))

  # select_r_session and list_r_sessions are reserved names
  tls$value[[1]]@name <- "select_r_session"
  expect_snapshot(set_server_tools(list(tls$value[[1]])), error = TRUE)
})

test_that("get_mcptools_tools works", {
  res <- get_mcptools_tools()
  expect_true(all(
    c("list_r_sessions", "select_r_session") %in% names(res)
  ))
})

test_that("get_mcptools_tools_as_json works", {
  res <- get_mcptools_tools_as_json()

  expect_true(all(vapply(
    res,
    function(x) all(c(c("name", "description", "inputSchema")) %in% names(x)),
    logical(1)
  )))
})

test_that("tool_as_json includes annotations", {
  tool <- ellmer::tool(
    function() "ok",
    "Read project state",
    name = "read_project",
    annotations = ellmer::tool_annotations(
      title = "Read Project",
      read_only_hint = TRUE,
      idempotent_hint = TRUE,
      open_world_hint = FALSE
    )
  )

  res <- tool_as_json(tool)

  expect_equal(res$title, "Read Project")

  expected_annotations <- list(
    title = "Read Project",
    readOnlyHint = TRUE,
    openWorldHint = FALSE,
    idempotentHint = TRUE
  )
  expect_setequal(names(res$annotations), names(expected_annotations))
  expect_equal(res$annotations[names(expected_annotations)], expected_annotations)
})

test_that("tool_as_json gates top-level title on protocol version", {
  tool <- ellmer::tool(
    function() "ok",
    "Read project state",
    name = "read_project",
    annotations = ellmer::tool_annotations(title = "Read Project")
  )

  res <- tool_as_json(tool, protocol_version = "2025-03-26")

  expect_false("title" %in% names(res))
  expect_equal(res$annotations$title, "Read Project")
})

test_that("tools/list preserves tool annotations", {
  old_server_tools <- the$server_tools
  withr::defer(the$server_tools <- old_server_tools)

  read_project <- ellmer::tool(
    function() "ok",
    "Read project state",
    name = "read_project",
    annotations = ellmer::tool_annotations(
      title = "Read Project",
      read_only_hint = TRUE,
      idempotent_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  delete_project <- ellmer::tool(
    function() "ok",
    "Delete project",
    name = "delete_project",
    annotations = ellmer::tool_annotations(
      destructive_hint = TRUE,
      open_world_hint = FALSE
    )
  )
  unannotated <- ellmer::tool(
    function() "ok",
    "No annotations",
    name = "unannotated"
  )
  set_server_tools(
    list(read_project, delete_project, unannotated),
    session_tools = FALSE
  )

  res <- handle_http_request_message(list(
    id = 1,
    method = "tools/list"
  ))
  tools <- setNames(res$result$tools, vapply(
    res$result$tools,
    function(x) x$name,
    character(1)
  ))

  read_project_annotations <- list(
    title = "Read Project",
    readOnlyHint = TRUE,
    openWorldHint = FALSE,
    idempotentHint = TRUE
  )
  expect_equal(tools$read_project$title, "Read Project")
  expect_setequal(
    names(tools$read_project$annotations),
    names(read_project_annotations)
  )
  expect_equal(
    tools$read_project$annotations[names(read_project_annotations)],
    read_project_annotations
  )

  delete_project_annotations <- list(
    openWorldHint = FALSE,
    destructiveHint = TRUE
  )
  expect_setequal(
    names(tools$delete_project$annotations),
    names(delete_project_annotations)
  )
  expect_equal(
    tools$delete_project$annotations[names(delete_project_annotations)],
    delete_project_annotations
  )
  expect_false("annotations" %in% names(tools$unannotated))
})

test_that("tools/list gates top-level title on negotiated protocol version", {
  old_server_tools <- the$server_tools
  withr::defer(the$server_tools <- old_server_tools)
  local_protocol_version("2025-03-26")

  tool <- ellmer::tool(
    function() "ok",
    "Read project state",
    name = "read_project",
    annotations = ellmer::tool_annotations(title = "Read Project")
  )
  set_server_tools(list(tool), session_tools = FALSE)

  res <- handle_http_request_message(list(
    id = 1,
    method = "tools/list"
  ))
  tool <- res$result$tools[[1]]

  expect_false("title" %in% names(tool))
  expect_equal(tool$annotations$title, "Read Project")
})

test_that("list_r_sessions() filters out integer error codes", {
  local_mocked_bindings(
    collect_aio_ = function(x) list("1: /home/user/myproject (RStudio)", 5L),
    socket = function(...) structure(list(), class = "nanoSocket"),
    monitor = function(...) structure(list(), class = "nanoMonitor"),
    dial = function(...) 0L,
    read_monitor = function(...) list(1L, 2L),
    recv_aio = function(...) structure(list(data = NULL), class = "recvAio"),
    send_aio = function(...) invisible(NULL),
    reap = function(...) invisible(NULL),
    .package = "nanonext"
  )
  result <- list_r_sessions()
  expect_equal(result, "1: /home/user/myproject (RStudio)")
})

test_that("parse_session_reply() parses structured replies", {
  reply <- as.character(to_json(list(
    session = 3L,
    wd = "/path/to/proj",
    description = "3: proj (Positron)"
  )))

  result <- parse_session_reply(reply)
  expect_equal(result$slot, 3L)
  expect_equal(result$wd, "/path/to/proj")
  expect_equal(result$description, "3: proj (Positron)")
})

test_that("parse_session_reply() falls back for pre-metadata replies", {
  result <- parse_session_reply("2: myproject (RStudio)")
  expect_equal(result$slot, 2L)
  expect_null(result$wd)
  expect_equal(result$description, "2: myproject (RStudio)")

  result <- parse_session_reply("mystery")
  expect_true(is.na(result$slot))
  expect_equal(result$description, "mystery")
})

test_that("discover_session_slot() prefers the working-directory match", {
  local_mocked_bindings(
    probe_sessions = function() {
      list(
        live = c(1L, 2L),
        sessions = list(
          list(slot = 1L, wd = "/proj/a", description = "1: a (Positron)"),
          list(slot = 2L, wd = "/proj/b", description = "2: b (Positron)")
        )
      )
    }
  )

  expect_equal(discover_session_slot("/proj/b"), 2L)
})

test_that("discover_session_slot() falls back to a sole live session", {
  # a busy session accepts the dial but can't reply, so it appears in `live`
  # without a corresponding session record
  local_mocked_bindings(
    probe_sessions = function() list(live = 4L, sessions = list())
  )

  expect_equal(discover_session_slot("/elsewhere"), 4L)
})

test_that("discover_session_slot() is NULL when there is no clear default", {
  probe <- list(
    live = c(1L, 2L),
    sessions = list(
      list(slot = 1L, wd = "/proj/a", description = "1: a (Positron)"),
      list(slot = 2L, wd = "/proj/b", description = "2: b (Positron)")
    )
  )
  local_mocked_bindings(probe_sessions = function() probe)

  expect_null(discover_session_slot("/elsewhere"))

  # two sessions in the same directory are also ambiguous
  probe$sessions[[2]]$wd <- "/proj/a"
  expect_null(discover_session_slot("/proj/a"))

  probe <- list(live = integer(), sessions = list())
  expect_null(discover_session_slot("/proj/a"))
})

test_that("ensure_session_connection() is TRUE when already connected", {
  local_mocked_bindings(
    stat = function(...) 1L,
    .package = "nanonext"
  )

  expect_true(ensure_session_connection())
})

test_that("ensure_session_connection() stays unconnected with no default", {
  local_mocked_bindings(
    stat = function(...) 0L,
    .package = "nanonext"
  )
  local_mocked_bindings(discover_session_slot = function(...) NULL)

  expect_false(ensure_session_connection())
})

test_that("ensure_session_connection() dials the discovered session", {
  pipes <- 0L
  dialed <- NULL
  local_mocked_bindings(
    stat = function(...) pipes,
    .package = "nanonext"
  )
  local_mocked_bindings(
    discover_session_slot = function(...) 7L,
    dial_session = function(slot, ...) {
      dialed <<- slot
      pipes <<- 1L
    }
  )

  expect_true(ensure_session_connection())
  expect_equal(dialed, 7L)
})
