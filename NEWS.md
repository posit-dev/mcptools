# mcptools 0.1.1

Addressed an issue in tests on `r-devel-linux-x86_64-fedora-clang`.

# mcptools 0.1.0

Initial CRAN submission.

Before the initial release of the package, mcptools was called acquaint and supplied a default set of tools from btw, currently a GitHub-only package, when R was used as an MCP server. The direction of the dependency has been reversed; to use the same functionality from before, transition `acquaint::mcp_server()` to `btw::btw_mcp_server()` and `acquaint::mcp_session()` to `btw::btw_mcp_session()`.
