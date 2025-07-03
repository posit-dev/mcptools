# set_server_tools can handle `tools` as path

    Code
      mcp_server(tmp_file)
    Condition
      Error in `mcp_server()`:
      ! `tools` must be a list of tools created with `ellmer::tool()` or a .R file path that returns a list of ellmer tools when sourced.

---

    Code
      mcp_server(tmp_file)
    Condition
      Error in `mcp_server()`:
      ! Sourcing the `tools` file 'x' failed.
      Caused by error:
      ! object 'boop' not found

---

    Code
      mcp_server(tmp_file)
    Condition
      Error in `mcp_server()`:
      ! `tools` must be a list of tools created with `ellmer::tool()` or a .R file path that returns a list of ellmer tools when sourced.

# set_server_tools errors informatively

    Code
      set_server_tools(tls$value[[1]])
    Condition
      Error:
      ! `tls$value[[1]]` must be a list of tools created with `ellmer::tool()` or a .R file path that returns a list of ellmer tools when sourced.
      i Did you mean to wrap `tls$value[[1]]` in `list()`?

---

    Code
      set_server_tools(list(tls$value[[1]]))
    Condition
      Error:
      ! The tool names list_r_sessions and select_r_session are reserved by mcptools.

