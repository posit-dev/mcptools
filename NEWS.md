# mcptools 0.2.0

## Server

* `mcp_server()` now supports HTTP transport in addition to stdio. Use `type = "http"` to start an HTTP server, with optional `host` and `port` arguments. For now, the implementation is authless.

* `mcp_server()` now formats tool results in the same way as ellmer (#78 by @gadenbuie).

* `mcp_server()` gains logical argument `session_tools`, allowing users to opt-out of presenting R session tools (that make it possible to communicate with `mcp_session()`s) to clients.

* Several tightenings-up of the implementation:
    -  JSON-RPC responses now retain an explicit `id = NULL` value, ensuring parse-error replies conform to the MCP specification.
    - `mcp_tools()` now sends and receives a `"notifications/initialized"` (#77 by @galachad).
    - The implementation now supports the 2025-06-18 protocol version, updated from 2024-11-05.

* `mcp_session()` now invisibly returns the nanonext socket used for communicating with the server.

## Client

- Notably, `mcp_tools()` did not gain an implementation of the HTTP transport. Instead, we now recommend the [mcp-remote](https://www.npmjs.com/package/mcp-remote) tool for serving local MCP servers via the HTTP transport in the documentation.

* `mcp_tools()` now errors more informatively when an MCP server process exits unexpectedly (#82).

# mcptools 0.1.1

* Addressed an issue in tests on `r-devel-linux-x86_64-fedora-clang`.

# mcptools 0.1.0

* Initial CRAN submission.

Before the initial release of the package, mcptools was called acquaint and supplied a default set of tools from btw, currently a GitHub-only package, when R was used as an MCP server. The direction of the dependency has been reversed; to use the same functionality from before, transition `acquaint::mcp_server()` to `btw::btw_mcp_server()` and `acquaint::mcp_session()` to `btw::btw_mcp_session()`.
