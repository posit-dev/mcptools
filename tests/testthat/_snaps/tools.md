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

