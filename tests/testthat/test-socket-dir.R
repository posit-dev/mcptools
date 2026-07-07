# socket_dir() ----------------------------------------------------------

test_that("socket_dir() respects MCPTOOLS_SOCKET_DIR override", {
  tmp <- file.path(tempdir(), "test-override")
  withr::defer(unlink(tmp, recursive = TRUE))
  withr::local_envvar(MCPTOOLS_SOCKET_DIR = tmp)

  expect_equal(socket_dir(), tmp)
  expect_true(dir.exists(tmp))
})

test_that("socket_dir() returns NULL on Windows", {
  withr::local_envvar(MCPTOOLS_SOCKET_DIR = NA)
  testthat::local_mocked_bindings(is_windows = function() TRUE)

  expect_null(socket_dir())
})

# socket_dir_default() --------------------------------------------------

test_that("socket_dir_default() uses XDG_RUNTIME_DIR on Linux", {
  skip_on_os("windows")
  testthat::local_mocked_bindings(is_macos = function() FALSE)
  withr::local_envvar(XDG_RUNTIME_DIR = "/run/user/1000")

  expect_equal(socket_dir_default(), "/run/user/1000/mcptools")
})

test_that("socket_dir_default() uses TMPDIR on Linux when no XDG", {
  skip_on_os("windows")
  testthat::local_mocked_bindings(is_macos = function() FALSE)
  withr::local_envvar(XDG_RUNTIME_DIR = NA, TMPDIR = "/local_scratch/job123")

  expect_match(socket_dir_default(), "^/local_scratch/job123/mcptools-")
})

test_that("socket_dir_default() falls back to /tmp on Linux", {
  skip_on_os("windows")
  testthat::local_mocked_bindings(is_macos = function() FALSE)
  withr::local_envvar(XDG_RUNTIME_DIR = NA, TMPDIR = NA)

  result <- socket_dir_default()
  expect_match(result, "^/tmp/mcptools-")
  # Should include username
  expect_match(result, Sys.info()[["user"]], fixed = TRUE)
})

test_that("socket_dir_default() uses TMPDIR on macOS", {
  skip_on_os("windows")
  testthat::local_mocked_bindings(is_macos = function() TRUE)
  withr::local_envvar(TMPDIR = "/var/folders/xx/test/T")

  expect_equal(socket_dir_default(), "/var/folders/xx/test/T/mcptools")
})

# ensure_socket_dir() ---------------------------------------------------

test_that("ensure_socket_dir() creates directory with 0700 perms", {
  skip_on_os("windows")
  tmp <- file.path(tempdir(), "test-perms-create")
  withr::defer(unlink(tmp, recursive = TRUE))

  ensure_socket_dir(tmp)
  expect_true(dir.exists(tmp))

  info <- file.info(tmp)
  # Group+other bits (octal 077 = decimal 63) should be zero
  expect_equal(bitwAnd(as.integer(info$mode), 63L), 0L)
})

test_that("ensure_socket_dir() tightens permissions if too open", {
  skip_on_os("windows")
  tmp <- file.path(tempdir(), "test-perms-tighten")
  dir.create(tmp, mode = "0755")
  withr::defer(unlink(tmp, recursive = TRUE))

  ensure_socket_dir(tmp)

  info <- file.info(tmp)
  expect_equal(bitwAnd(as.integer(info$mode), 63L), 0L)
})

# socket_url() ----------------------------------------------------------

test_that("socket_url() returns ipc:// path on Unix", {
  skip_on_os("windows")
  tmp <- file.path(tempdir(), "test-url")
  withr::defer(unlink(tmp, recursive = TRUE))
  withr::local_envvar(MCPTOOLS_SOCKET_DIR = tmp)

  url <- socket_url()
  expect_match(url, "^ipc://")
  expect_match(url, "mcptools-socket$")
})

test_that("socket_url() returns named pipe format on Windows", {
  testthat::local_mocked_bindings(is_windows = function() TRUE)

  expect_equal(socket_url(), "ipc://mcptools-socket")
})

# cleanup_session_socket() ----------------------------------------------

test_that("cleanup_session_socket() removes socket file", {
  skip_on_os("windows")
  tmp <- file.path(tempdir(), "test-cleanup")
  dir.create(tmp, showWarnings = FALSE)
  withr::defer(unlink(tmp, recursive = TRUE))

  old_url <- the$socket_url
  old_session <- the$session
  withr::defer({
    the$socket_url <- old_url
    the$session <- old_session
  })

  the$socket_url <- sprintf("ipc://%s/mcptools-socket", tmp)
  the$session <- 42L

  # Create a fake socket file
  socket_file <- file.path(tmp, "mcptools-socket42")
  file.create(socket_file)
  expect_true(file.exists(socket_file))

  cleanup_session_socket()
  expect_false(file.exists(socket_file))
})

test_that("cleanup_session_socket() is no-op when no session active", {
  old_session <- the$session
  the$session <- NULL
  withr::defer(the$session <- old_session)

  expect_no_error(cleanup_session_socket())
})

test_that("cleanup_session_socket() is no-op for non-ipc sockets", {
  old_url <- the$socket_url
  old_session <- the$session
  withr::defer({
    the$socket_url <- old_url
    the$session <- old_session
  })

  the$socket_url <- "abstract://mcptools-socket"
  the$session <- 1L

  # Should not error or attempt file operations
  expect_no_error(cleanup_session_socket())
})

# clean_stale_sockets() -------------------------------------------------

test_that("clean_stale_sockets() removes stale socket files", {
  skip_on_os("windows")

  tmp <- file.path(tempdir(), "test-stale")
  dir.create(tmp, showWarnings = FALSE, mode = "0700")
  withr::defer(unlink(tmp, recursive = TRUE))

  # Create a real stale socket: listen then close (leaves file behind)
  sock <- nanonext::socket("poly")
  socket_path <- file.path(tmp, "mcptools-socket99")
  nanonext::listen(sock, url = sprintf("ipc://%s", socket_path))
  close(sock)

  if (file.exists(socket_path)) {
    clean_stale_sockets(tmp)
    expect_false(file.exists(socket_path))
  } else {
    # Socket was auto-cleaned (possible on some nanonext versions)
    succeed("Socket auto-cleaned by nanonext")
  }
})

test_that("clean_stale_sockets() does NOT remove active sockets", {
  skip_on_os("windows")
  # Use a short path to stay within Unix socket 108-char limit
  tmp <- file.path("/tmp", paste0("mcp-test-", Sys.getpid()))
  dir.create(tmp, showWarnings = FALSE, mode = "0700")
  withr::defer(unlink(tmp, recursive = TRUE))

  # Spawn a background R process that listens and responds to pings
  # (mimics what mcp_session() does)
  bg <- callr::r_bg(function(tmp) {
    sock <- nanonext::socket("poly")
    socket_path <- file.path(tmp, "mcptools-socket1")
    nanonext::listen(sock, url = sprintf("ipc://%s", socket_path))

    # Simple recv-respond loop (mirrors handle_message_from_server)
    for (j in seq_len(100)) {
      msg <- nanonext::recv(sock, mode = "serial", block = 200L)
      if (!nanonext::is_error_value(msg)) {
        nanonext::send(sock, "1: /test (Test)", mode = "raw")
      }
    }
    nanonext::reap(sock)
  }, args = list(tmp = tmp))
  withr::defer(bg$kill())

  # Give the subprocess time to start listening
  Sys.sleep(1)
  socket_path <- file.path(tmp, "mcptools-socket1")
  skip_if(!file.exists(socket_path), "Background session did not start")

  # Should NOT remove it -- the background process responds to pings
  clean_stale_sockets(tmp)
  expect_true(file.exists(socket_path))
})

test_that("clean_stale_sockets() is no-op for NULL or missing dir", {
  expect_no_error(clean_stale_sockets(NULL))
  expect_no_error(clean_stale_sockets("/nonexistent/path"))
})

test_that("clean_stale_sockets() ignores non-socket files", {
  skip_on_os("windows")
  tmp <- file.path(tempdir(), "test-stale-ignore")
  dir.create(tmp, showWarnings = FALSE)
  withr::defer(unlink(tmp, recursive = TRUE))

  # These should NOT be touched (don't match the pattern)
  other_file <- file.path(tmp, "other-file.txt")
  token_file <- file.path(tmp, ".mcptools-token")
  file.create(other_file)
  file.create(token_file)

  clean_stale_sockets(tmp)
  expect_true(file.exists(other_file))
  expect_true(file.exists(token_file))
})
