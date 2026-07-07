# Socket directory management for per-user IPC isolation.
#
# On Linux and macOS, nanonext IPC sockets are placed inside a user-private
# directory (0700 permissions) so that other users on a shared system cannot
# discover or connect to sessions. This prevents cross-user code execution
# via the MCP session protocol.

#' Determine the socket directory for IPC communication
#' @noRd
socket_dir <- function() {
  # Allow explicit override for containers, shared-team use, and testing
  override <- Sys.getenv("MCPTOOLS_SOCKET_DIR", unset = "")
  if (nzchar(override)) {
    ensure_socket_dir(override)
    return(override)
  }

  if (is_windows()) {
    # Windows uses named pipes, no directory needed
    return(NULL)
  }

  path <- socket_dir_default()
  ensure_socket_dir(path)

  path
}

#' Default socket directory per platform
#' @noRd
socket_dir_default <- function() {
  if (is_macos()) {
    # macOS: $TMPDIR is already per-user (/var/folders/xx/.../T/)
    tmpdir <- Sys.getenv("TMPDIR", unset = "")
    if (nzchar(tmpdir)) {
      return(file.path(tmpdir, "mcptools"))
    }
    # macOS fallback (should rarely fire -- TMPDIR is always set on macOS)
    return(file.path(tempdir(), "mcptools"))
  }

  # Linux: try XDG_RUNTIME_DIR first (per-user tmpfs, 0700, systemd-managed)
  xdg <- Sys.getenv("XDG_RUNTIME_DIR", unset = "")
  if (nzchar(xdg)) {
    return(file.path(xdg, "mcptools"))
  }

  # fallback: $TMPDIR (job schedulers set this to node-local scratch)
  tmpdir <- Sys.getenv("TMPDIR", unset = "")
  if (nzchar(tmpdir)) {
    username <- Sys.info()[["user"]]
    return(file.path(tmpdir, paste0("mcptools-", username)))
  }

  # Universal fallback: /tmp with user-private subdirectory
  username <- Sys.info()[["user"]]
  file.path("/tmp", paste0("mcptools-", username))
}

#' Create socket directory with restrictive permissions
#' @noRd
ensure_socket_dir <- function(path) {
  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, mode = "0700")
  } else if (is_unix()) {
    # Verify permissions are restrictive (owner-only)
    info <- file.info(path)
    if (!is.na(info$mode)) {
      # Check group+other permission bits (octal 077 = decimal 63)
      # If any are set, tighten to 0700
      if (bitwAnd(as.integer(info$mode), 63L) != 0L) {
        Sys.chmod(path, mode = "0700")
      }
    }
  }
  invisible(path)
}

#' Clean up stale socket files from crashed sessions
#'
#' Uses ping-based detection: dial all socket files, monitor for pipes,
#' send an empty ping, and wait 100ms. Live local IPC sessions respond in
#' <10ms; anything that times out is stale and safe to remove.
#'
#' This approach works on both Linux and macOS (unlike dial-return-code
#' checking, which always returns 0 on macOS due to async dialer queuing).
#' @noRd
clean_stale_sockets <- function(dir) {
  if (is.null(dir) || !dir.exists(dir)) {
    return(invisible())
  }

  files <- list.files(dir, pattern = "^mcptools-socket\\d+$", full.names = TRUE)
  if (length(files) == 0L) {
    return(invisible())
  }

  sock <- nanonext::socket("poly")
  on.exit(nanonext::reap(sock))
  cv <- nanonext::cv()
  monitor <- nanonext::monitor(sock, cv)

  for (f in files) {
    nanonext::dial(sock, url = sprintf("ipc://%s", f), autostart = NA, fail = "none")
  }

  pipes <- nanonext::read_monitor(monitor)

  if (length(pipes) == 0L) {
    # No connections at all — all files are stale
    try(unlink(files), silent = TRUE)
    return(invisible())
  }

  # Ping each pipe — live sessions respond in <10ms; 100ms is safe headroom
  # All pings fire in parallel so N stale sockets cost only 100ms total
  aios <- lapply(
    pipes,
    function(p) nanonext::recv_aio(sock, mode = "string", timeout = 100L)
  )
  lapply(
    pipes,
    function(p) nanonext::send_aio(sock, character(), mode = "serial", pipe = p)
  )
  results <- nanonext::collect_aio_(aios)

  # pipes returned in dial order, matching files order
  for (i in seq_along(results)) {
    if (is.integer(results[[i]])) {
      # Timeout (5L) or error — no live listener, safe to remove
      try(unlink(files[[i]]), silent = TRUE)
    }
  }

  invisible()
}

#' Remove the socket file for the current session
#' @noRd
cleanup_session_socket <- function() {
  if (is.null(the$session) || is.null(the$socket_url)) {
    return(invisible())
  }

  # Only filesystem sockets need cleanup (not abstract:// or named pipes)
  url <- sprintf("%s%d", the$socket_url, the$session)
  if (!startsWith(url, "ipc://")) {
    return(invisible())
  }

  socket_file <- sub("^ipc://", "", url)
  if (file.exists(socket_file)) {
    try(unlink(socket_file), silent = TRUE)
  }
  invisible()
}

#' Construct the socket URL prefix for this platform/user
#' @noRd
socket_url <- function() {
  if (is_windows()) {
    return("ipc://mcptools-socket")
  }
  dir <- socket_dir()
  sprintf("ipc://%s/mcptools-socket", dir)
}

# Platform detection helpers ------------------------------------------------

is_windows <- function() {
  identical(.Platform$OS.type, "windows")
}

is_macos <- function() {
  identical(Sys.info()[["sysname"]], "Darwin")
}
