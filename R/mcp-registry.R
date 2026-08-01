# MCP extension registry
# ------------------------------------------------------------------------------
# Enables *additive* MCP method + capability handlers so that each protocol
# feature area (resources, prompts, completion, logging, ...) can live in its
# own R/mcp-<feature>.R file WITHOUT editing the central request dispatchers.
#
# A feature file defines:
#   * one or more handler functions, and
#   * a registrar named `.register_mcp_<feature>()` that calls
#     `register_mcp_method()` / `register_mcp_capability()`.
#
# All `.register_mcp_*` registrars are auto-discovered and invoked from
# `.onLoad()` via `mcp_run_registrars()`. Adding a feature therefore requires no
# changes to shared dispatch code, which keeps parallel feature branches
# conflict-free.
#
# Handler contract:
#   handler <- function(data, protocol_version, transport) { ... }
#     data             parsed JSON-RPC request/notification (list)
#     protocol_version negotiated protocol version string
#     transport        "http" or "stdio"
#   Return value for a *request* (data$id present):
#     * a list  -> sent as the JSON-RPC `result`
#     * a `jsonrpc_error()` object -> sent as the JSON-RPC `error`
#   Return value for a *notification* (data$id absent) is ignored.

# Register (or replace) a handler for a JSON-RPC method.
register_mcp_method <- function(method, handler) {
  stopifnot(is_string(method), is.function(handler))
  the$mcp_methods[[method]] <- handler
  invisible()
}

# Merge a capability fragment into the advertised `capabilities` map.
# `fragment` is a named list, e.g. list(resources = named_list(subscribe = TRUE)).
register_mcp_capability <- function(fragment) {
  stopifnot(is.list(fragment))
  the$mcp_capabilities <- utils::modifyList(the$mcp_capabilities, fragment)
  invisible()
}

# Construct a classed JSON-RPC error object for handlers to return.
jsonrpc_error <- function(code, message, data = NULL) {
  structure(
    drop_nulls(list(code = code, message = message, data = data)),
    class = "jsonrpc_error"
  )
}

# Discover and run every `.register_mcp_*` registrar in the namespace.
# Called once from `.onLoad()`.
mcp_run_registrars <- function(pkgname = "mcptools") {
  the$mcp_methods <- the$mcp_methods %||% list()
  the$mcp_capabilities <- the$mcp_capabilities %||% list()
  ns <- tryCatch(getNamespace(pkgname), error = function(e) NULL)
  if (is.null(ns)) {
    return(invisible())
  }
  regs <- sort(ls(ns, all.names = TRUE))
  regs <- regs[startsWith(regs, ".register_mcp_")]
  for (nm in regs) {
    fn <- get(nm, envir = ns)
    if (is.function(fn)) {
      fn()
    }
  }
  invisible()
}

# Look up and invoke a registered handler for a *request* (data$id present).
# Returns a JSON-RPC response list, or NULL when no handler is registered
# (the caller then emits -32601 Method not found).
dispatch_mcp_method <- function(data, protocol_version, transport = "http") {
  handler <- the$mcp_methods[[data$method]]
  if (is.null(handler)) {
    return(NULL)
  }
  res <- handler(data, protocol_version = protocol_version, transport = transport)
  if (inherits(res, "jsonrpc_error")) {
    return(jsonrpc_response(data$id, error = unclass(res)))
  }
  jsonrpc_response(data$id, result = res)
}

# Invoke a registered handler for a *notification* (data$id absent), for side
# effects only. Safe no-op when unregistered.
dispatch_mcp_notification <- function(data, protocol_version, transport = "http") {
  handler <- the$mcp_methods[[data$method]]
  if (!is.null(handler)) {
    handler(data, protocol_version = protocol_version, transport = transport)
  }
  invisible(NULL)
}
