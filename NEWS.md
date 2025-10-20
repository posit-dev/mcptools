# mcptools (development version)

* `mcp_server()` now supports HTTP transport in addition to stdio. Use `type = "http"` to start an HTTP server, with optional `host` and `port` arguments. For now, the implementation is authless.

* `mcp_tools()` now supports connecting to HTTP-based MCP servers. Configure servers with a `url` field in the config file instead of `command`/`args`.

* JSON-RPC responses now retain an explicit `id = NULL` value, ensuring parse-error replies conform to the MCP specification.

* `mcp_server()` now formats tool results in the same way as ellmer (#78 by @gadenbuie).

* `mcp_tools()` now sends and receives a `"notifications/initialized"` (#77 by @galachad).

* `mcp_session()` now returns invisibly the nanonext socket used for communicating with the server.

* `mcp_server()` gains logical argument `session_tools`, allowing users to opt-out of presenting R sessions tools to clients.

# mcptools 0.1.1

* Addressed an issue in tests on `r-devel-linux-x86_64-fedora-clang`.

# mcptools 0.1.0

* Initial CRAN submission.

Before the initial release of the package, mcptools was called acquaint and supplied a default set of tools from btw, currently a GitHub-only package, when R was used as an MCP server. The direction of the dependency has been reversed; to use the same functionality from before, transition `acquaint::mcp_server()` to `btw::btw_mcp_server()` and `acquaint::mcp_session()` to `btw::btw_mcp_session()`.
