# mcp_set_tools works

    Code
      mcp_set_tools("boop")
    Condition
      Error in `mcp_set_tools()`:
      ! `x` must be a list of tools created with `ellmer::tool()`.

---

    Code
      mcp_set_tools(tool_rnorm)
    Condition
      Error in `mcp_set_tools()`:
      ! `x` must be a list of tools created with `ellmer::tool()`.
      i Did you mean to wrap `x` in `list()`?

---

    Code
      mcp_set_tools(list(tool_rnorm))
    Condition
      Error in `mcp_set_tools()`:
      ! The tool names list_r_sessions and select_r_session are reserved by acquaint.
