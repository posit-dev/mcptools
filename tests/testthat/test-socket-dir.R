# socket_dir() ----------------------------------------------------------

test_that("socket_dir() respects MCPTOOLS_SOCKET_DIR override and is pure", {
  tmp <- file.path(tempdir(), "test-override")
  withr::defer(unlink(tmp, recursive = TRUE))
  withr::local_envvar(MCPTOOLS_SOCKET_DIR = tmp)

  expect_equal(socket_dir(), tmp)
  # computing the path must not touch the filesystem
  expect_false(dir.exists(tmp))
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

test_that("ensure_socket_dir() aborts on a symlinked directory", {
  skip_on_os("windows")
  target <- file.path(tempdir(), "test-symlink-target")
  link <- file.path(tempdir(), "test-symlink-link")
  dir.create(target, showWarnings = FALSE, mode = "0700")
  file.symlink(target, link)
  withr::defer(unlink(c(target, link), recursive = TRUE))

  expect_error(ensure_socket_dir(link), "is a symlink")
})

test_that("ensure_socket_dir() aborts when the directory is not owned by us", {
  skip_on_os("windows")
  tmp <- file.path(tempdir(), "test-foreign-owner")
  dir.create(tmp, showWarnings = FALSE, mode = "0700")
  withr::defer(unlink(tmp, recursive = TRUE))

  # simulate a directory owned by another uid
  testthat::local_mocked_bindings(
    file.info = function(path, ...) {
      data.frame(uid = if (identical(path, tmp)) 999999L else 1L, mode = 448L)
    },
    .package = "base"
  )

  expect_error(ensure_socket_dir(tmp), "not owned by the current user")
})

test_that("ensure_socket_dir() verifies a directory that lost the create race", {
  skip_on_os("windows")
  tmp <- file.path(tempdir(), "test-race")
  dir.create(tmp, showWarnings = FALSE, mode = "0700")
  withr::defer(unlink(tmp, recursive = TRUE))

  # dir.exists FALSE forces the create branch; dir.create FALSE simulates
  # another user winning the race, leaving a directory we do not own
  testthat::local_mocked_bindings(
    dir.exists = function(...) FALSE,
    dir.create = function(...) FALSE,
    file.info = function(path, ...) {
      data.frame(uid = if (identical(path, tmp)) 999999L else 1L, mode = 448L)
    },
    .package = "base"
  )

  expect_error(ensure_socket_dir(tmp), "not owned by the current user")
})

test_that("ensure_socket_dir() is a no-op for NULL or on Windows", {
  expect_no_error(ensure_socket_dir(NULL))

  testthat::local_mocked_bindings(is_windows = function() TRUE)
  expect_no_error(ensure_socket_dir("/some/path"))
})

# socket_dir_in_use() ---------------------------------------------------

test_that("socket_dir_in_use() derives the directory from the socket URL", {
  skip_on_os("windows")
  old <- the$socket_url
  withr::defer(the$socket_url <- old)

  the$socket_url <- "ipc:///abs/dir/mcptools-socket"
  expect_equal(socket_dir_in_use(), "/abs/dir")
})

test_that("socket_dir_in_use() aborts on a non-absolute socket directory", {
  skip_on_os("windows")
  old <- the$socket_url
  withr::defer(the$socket_url <- old)

  the$socket_url <- "ipc://relative/mcptools-socket"
  expect_error(socket_dir_in_use(), "absolute path")
})

test_that("socket_dir_in_use() is NULL on Windows", {
  testthat::local_mocked_bindings(is_windows = function() TRUE)
  expect_null(socket_dir_in_use())
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

test_that("socket_url() returns a user-scoped named pipe on Windows", {
  testthat::local_mocked_bindings(is_windows = function() TRUE)

  expect_match(socket_url(), "^ipc://mcptools-.+-socket$")
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

# reclaim_stale_socket() ------------------------------------------------

test_that("reclaim_stale_socket() removes a stale socket file", {
  skip_on_os("windows")
  tmp <- file.path(tempdir(), "test-reclaim-stale")
  dir.create(tmp, showWarnings = FALSE, mode = "0700")
  withr::defer(unlink(tmp, recursive = TRUE))

  stale <- file.path(tmp, "mcptools-socket1")
  file.create(stale)

  expect_true(reclaim_stale_socket(sprintf("ipc://%s", stale)))
  expect_false(file.exists(stale))
})

test_that("reclaim_stale_socket() spares a live (even busy) listener", {
  skip_on_os("windows")
  skip_if_not_installed("callr")
  # short path to stay within the Unix socket path length limit
  tmp <- file.path("/tmp", paste0("mcp-reclaim-", Sys.getpid()))
  dir.create(tmp, showWarnings = FALSE, mode = "0700")
  withr::defer(unlink(tmp, recursive = TRUE))

  socket_path <- file.path(tmp, "mcptools-socket1")

  # only listens, never answers: the busy-session case a naive ping would
  # misread as stale
  bg <- callr::r_bg(
    function(path) {
      sock <- nanonext::socket("poly")
      nanonext::listen(sock, url = sprintf("ipc://%s", path))
      Sys.sleep(30)
    },
    args = list(path = socket_path)
  )
  withr::defer(bg$kill())

  deadline <- Sys.time() + 5
  while (!file.exists(socket_path) && Sys.time() < deadline) Sys.sleep(0.05)
  skip_if(!file.exists(socket_path), "Background listener did not start")

  expect_false(reclaim_stale_socket(sprintf("ipc://%s", socket_path)))
  expect_true(file.exists(socket_path))
})

test_that("reclaim_stale_socket() is FALSE when there is no file to reclaim", {
  expect_false(reclaim_stale_socket("ipc:///nonexistent/mcptools-socket1"))
  # named-pipe URL, no filesystem path
  expect_false(reclaim_stale_socket("ipc://mcptools-socket1"))
})

test_that("mcp_session() advances past a live slot and reclaims a stale one", {
  skip_on_os("windows")
  tmp <- file.path("/tmp", paste0("mcp-mixed-", Sys.getpid()))
  dir.create(tmp, showWarnings = FALSE, mode = "0700")
  withr::defer(unlink(tmp, recursive = TRUE))

  old_url <- the$socket_url
  old_socket <- the$session_socket
  old_session <- the$session
  withr::defer({
    nanonext::reap(the$session_socket)
    the$socket_url <- old_url
    the$session_socket <- old_socket
    the$session <- old_session
  })
  the$socket_url <- sprintf("ipc://%s/mcptools-socket", tmp)

  # live listener at slot 1, stale leftover at slot 2
  live <- nanonext::socket("poly")
  nanonext::listen(live, url = sprintf("%s%d", the$socket_url, 1L))
  withr::defer(nanonext::reap(live))
  file.create(file.path(tmp, "mcptools-socket2"))

  mcp_session()

  expect_equal(the$session, 2L)
  expect_true(file.exists(file.path(tmp, "mcptools-socket1")))
})
