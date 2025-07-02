# jsonrpc_response works

    Code
      .res <- jsonrpc_response("789", result = "success", error = list(code = -32603,
        message = "error"))
    Condition
      Warning in `jsonrpc_response()`:
      Either `result` or `error` must be provided, but not both.

---

    Code
      .res <- jsonrpc_response("000")
    Condition
      Warning in `jsonrpc_response()`:
      Either `result` or `error` must be provided, but not both.

