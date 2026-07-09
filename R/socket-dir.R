# Socket directory management for per-user IPC isolation.
#
# On Linux and macOS, nanonext IPC sockets are placed inside a user-private
# directory (0700 permissions) so that other users on a shared system cannot
# discover or connect to sessions. This prevents cross-user code execution
# via the MCP session protocol.

# Compute the per-user socket directory. Pure: creation and permission checks
# happen in ensure_socket_dir() at socket-use time, not here (and not at load).
# Returns NULL on Windows, which uses named pipes rather than a directory.
socket_dir <- function() {
  # Allow explicit override for containers, shared-team use, and testing
  override <- Sys.getenv("MCPTOOLS_SOCKET_DIR", unset = "")
  if (nzchar(override)) {
    return(override)
  }

  if (is_windows()) {
    return(NULL)
  }

  socket_dir_default()
}

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

# Create the socket directory (0700) or, if it already exists, verify we can
# trust it before reusing it. A predictable fallback path such as
# /tmp/mcptools-<user> can be pre-created by another user; a symlink or foreign
# owner means we must not place sockets there, and Sys.chmod() by a non-owner
# fails silently, so we abort rather than proceed into an attacker-owned dir.
ensure_socket_dir <- function(path, call = caller_env()) {
  if (is.null(path) || is_windows()) {
    return(invisible(path))
  }

  if (!dir.exists(path)) {
    dir.create(path, recursive = TRUE, mode = "0700")
    return(invisible(path))
  }

  if (nzchar(Sys.readlink(path))) {
    cli::cli_abort(
      "Socket directory {.path {path}} is a symlink; refusing to use it.",
      call = call
    )
  }

  # Compare uids rather than usernames: file.info()$uname is NA for a uid with
  # no passwd entry (containers with arbitrary uids), which would miscompare.
  # tempdir() is created by R as the current user, so its uid is ours.
  if (!identical(file.info(path)$uid, file.info(tempdir())$uid)) {
    cli::cli_abort(
      "Socket directory {.path {path}} is not owned by the current user.",
      call = call
    )
  }

  # tighten if any group/other bits are set (octal 077 = decimal 63)
  info <- file.info(path)
  if (!is.na(info$mode) && bitwAnd(as.integer(info$mode), 63L) != 0L) {
    Sys.chmod(path, mode = "0700")
  }

  invisible(path)
}

# Reclaim a socket slot whose file is stale. A live listener accepts a pipe at
# the NNG layer even while its R process is busy, so a refused synchronous dial
# is a busy-proof test that no listener remains. On refusal we unlink the
# leftover file so the slot can be relisted; returns TRUE when one was removed.
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

# Remove the socket file for the current session on clean exit.
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

# Filesystem path backing an ipc:// URL, or NULL when there is no file to
# manage (named pipes on Windows, or non-ipc:// URLs).
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

# Construct the socket URL prefix for this platform/user.
socket_url <- function() {
  if (is_windows()) {
    # Named pipes share a global namespace, so scope by user to avoid
    # cross-user collisions; sanitize because usernames may contain spaces.
    # This is not a security boundary on Windows (see ?mcp_session).
    user <- gsub("[^A-Za-z0-9._-]", "_", Sys.info()[["user"]])
    return(sprintf("ipc://mcptools-%s-socket", user))
  }
  sprintf("ipc://%s/mcptools-socket", socket_dir())
}

# Platform detection helpers ------------------------------------------------

is_windows <- function() {
  identical(.Platform$OS.type, "windows")
}

is_macos <- function() {
  identical(Sys.info()[["sysname"]], "Darwin")
}
