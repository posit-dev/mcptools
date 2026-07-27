# Keep socket directories created during tests (including by spawned
# subprocesses, which inherit the envvar) inside R's session tempdir, which R
# removes on exit. The default locations live directly in TMPDIR and would be
# flagged as detritus by R CMD check.
withr::local_envvar(
  MCPTOOLS_SOCKET_DIR = file.path(tempdir(), "mcptools"),
  .local_envir = teardown_env()
)

old_socket_url <- the$socket_url
the$socket_url <- socket_url()
withr::defer(the$socket_url <- old_socket_url, teardown_env())
