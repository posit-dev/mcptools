# mcptools (development version)

* HTTP `mcp_server()` requests now honor the `MCP-Protocol-Version` header,
  return `400 Bad Request` for unsupported protocol versions, and avoid using
  protocol negotiation from one HTTP client to shape responses for another.

* JSON output now serializes R `NULL` values as JSON `null`, fixing JSON-RPC
  responses with null request IDs.

* `mcp_server()` no longer falls through after reporting `Invalid Request` for
  invalid stdio client messages.

* mcptools can now run as a Posit Connect R API engine. Add `_server.yml`
  with `engine: mcptools`, point `tools` to an `.R` file returning
  `ellmer::tool()` objects, and deploy with
  `rsconnect::deployAPI(".", contentCategory = "mcp")`.

* Forwarded `mcp_session()` tool calls now return JSON-RPC errors when the
  selected R session does not respond within two minutes, rather than hanging
  indefinitely. Configure the timeout with the
  `mcptools.session_response_timeout_seconds` option or the
  `MCPTOOLS_SESSION_RESPONSE_TIMEOUT_SECONDS` environment variable. Session
  receive errors are also logged instead of silently discarded (#98).

* `mcp_server()` now returns `structuredContent` alongside serialized JSON text
  for successful tool results that are naturally represented as JSON objects
  when using MCP protocol version 2025-06-18 or later (#104).

* `mcp_server()` now includes ellmer tool annotations in `tools/list`
  responses, preserving MCP safety hints such as `title`, `readOnlyHint`,
  `destructiveHint`, `idempotentHint`, and `openWorldHint` (#100, #105).

* `mcp_server()` can now return inline image content from tools that produce
  `ellmer::ContentImageInline` results, including mixed text and image content
  (#96, #102).

* `mcp_tools()` now converts MCP tool-result content blocks into ellmer-native
  text and image content, allowing ellmer chats to receive image results from
  MCP tools.

* `mcp_tools()` now launches MCP server processes with an allowlisted
  environment plus configured `env` variables. Previously, servers without
  configured `env` inherited the full R process environment, while servers with
  configured `env` received only those variables. The new behavior more closely
  matches reference MCP SDKs, reduces accidental credential exposure, and fixes
  Windows startup failures when `env` is configured. Servers that need
  additional non-allowlisted variables should list them in `env` (#62).

# mcptools 0.2.1

* `mcp_server()` now ensures that `inputSchema` always includes a `properties`
  field, even for tools with no arguments (#91 by @itkonen).

* `mcp_server()` now negotiates the protocol version with clients, supporting versions 2024-11-05 through 2025-11-25 (#92 by @itkonen).

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
