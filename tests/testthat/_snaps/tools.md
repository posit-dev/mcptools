# set_acquaint_tools works

    Code
      set_acquaint_tools("boop")
    Condition
      Error in `set_acquaint_tools()`:
      ! `x` must be a list of tools created with `ellmer::tool()`.

---

    Code
      set_acquaint_tools(tool_rnorm)
    Condition
      Error in `set_acquaint_tools()`:
      ! `x` must be a list of tools created with `ellmer::tool()`.
      i Did you mean to wrap `x` in `list()`?

---

    Code
      set_acquaint_tools(list(tool_rnorm))
    Condition
      Error in `set_acquaint_tools()`:
      ! The tool names list_r_sessions and select_r_session are reserved by acquaint.

