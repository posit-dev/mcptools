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

#' Reclaim a socket slot whose file is stale
#'
#' A live listener accepts a pipe at the NNG layer even while its R process is
#' busy, so a refused synchronous dial is a busy-proof test that no listener
#' remains. On refusal we unlink the leftover file so the slot can be relisted;
#' returns `TRUE` when a stale file was removed.
#' @noRd
reclaim_stale_socket <- function(url) {
  file <- ipc_socket_file(url)
  if (is.null(file) || !file.exists(file)) {
    return(FALSE)
  }

  sock <- nanonext::socket("poly")
  on.exit(nanonext::reap(sock))
  rc <- nanonext::dial(sock, url = url, autostart = NA, fail = "none")

  if (nanonext::is_error_value(rc)) {
    try(unlink(file), silent = TRUE)
    return(TRUE)
  }

  FALSE
}

#' Remove the socket file for the current session
#' @noRd
cleanup_session_socket <- function() {
  if (is.null(the$session) || is.null(the$socket_url)) {
    return(invisible())
  }

  file <- ipc_socket_file(sprintf("%s%d", the$socket_url, the$session))
  if (!is.null(file) && file.exists(file)) {
    try(unlink(file), silent = TRUE)
  }
  invisible()
}

#' Filesystem path backing an `ipc://` URL, or `NULL` when there is no file to
#' manage (named pipes on Windows, or non-`ipc://` URLs).
#' @noRd
ipc_socket_file <- function(url) {
  if (!startsWith(url, "ipc://")) {
    return(NULL)
  }
  path <- sub("^ipc://", "", url)
  # Windows named pipes are also ipc:// but have no on-disk path
  if (!startsWith(path, "/")) {
    return(NULL)
  }
  path
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
