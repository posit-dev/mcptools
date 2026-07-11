# mcptools (development version)


* The server now chooses its R session at tool-call time rather than always
  connecting to the first session: it prefers the session whose working
  directory matches its own (clients like Claude Code and Posit Assistant
  launch the server in the project directory), falling back to the only
  running session. When several sessions are running and none matches, tools
  execute in the server's own R process until the client calls
  `select_r_session`. Previously, a second client + session pair in another
  project window would silently execute tools in the first project's
  session (#114).

* Sessions now use per-user filesystem IPC sockets in an owner-only (0700)
  directory instead of a shared address. On multi-user Linux hosts (e.g. Posit
  Workbench) the previous default let any local user connect to another user's
  `mcp_session()` and execute tools in it; sessions are now isolated by Unix
  user. The socket directory follows `MCPTOOLS_SOCKET_DIR` >
  `XDG_RUNTIME_DIR/mcptools/` > `$TMPDIR/mcptools-<user>/` >
  `/tmp/mcptools-<user>/`. Reported and prototyped by @kwbyron-lilly (#114).

* Socket files left behind by a crashed session are now reclaimed automatically:
  the next session that needs the slot detects the dead file and reuses it.

* `list_r_sessions()` no longer returns spurious `"5"` entries when a session is
  slow to respond to discovery probes.

* `mcp_tools()` now initiates the MCP OAuth authorization-code flow automatically
  when a remote server configured with only a `url` answers an unauthenticated
  request with a `401` challenge. Previously, connecting to such a server required
  either a static `Authorization` header or an explicit `oauth` block; the `oauth`
  block is now needed only to override defaults.


# mcptools 1.0.0

## `mcp_server()`

**New features**:

* mcptools can now run as a Posit Connect R API engine. Add a `_server.yml`
  with `engine: mcptools`, point `tools` to an `.R` file returning
  `ellmer::tool()` objects, and deploy with
  `rsconnect::deployAPI(".", contentCategory = "mcp")`.

* `mcp_server()` can now return inline image content from tools that produce
  `ellmer::ContentImageInline` results, including mixed text and image content
  (#96, #102).

* `mcp_server()` now returns `structuredContent` alongside serialized JSON text
  for successful tool results that are naturally represented as JSON objects,
  when using MCP protocol version 2025-06-18 or later (#104).

* `mcp_server()` now includes ellmer tool annotations in `tools/list`
  responses, preserving MCP safety hints such as `title`, `readOnlyHint`,
  `destructiveHint`, `idempotentHint`, and `openWorldHint` (#100, #105).

**Bug fixes**:

* HTTP `mcp_server()` requests now honor the `MCP-Protocol-Version` header,
  return `400 Bad Request` for unsupported protocol versions, and no longer let
  protocol negotiation from one HTTP client shape responses for another.

* JSON output now serializes R `NULL` values as JSON `null`, fixing JSON-RPC
  responses with null request IDs.

* `mcp_server()` no longer falls through after reporting `Invalid Request` for
  invalid stdio client messages.

* Forwarded `mcp_session()` tool calls now return JSON-RPC errors when the
  selected R session does not respond within two minutes, rather than hanging
  indefinitely. Configure the timeout with the
  `mcptools.session_response_timeout_seconds` option or the
  `MCPTOOLS_SESSION_RESPONSE_TIMEOUT_SECONDS` environment variable. Session
  receive errors are also logged instead of silently discarded (#98).

## `mcp_tools()`

**New features**:

* `mcp_tools()` can now connect directly to remote Streamable HTTP MCP servers,
  configured with `url` instead of `command`. Static `headers` are supported for
  token auth, and full OAuth 2.1 (authorization-server discovery, Dynamic Client
  Registration, PKCE, and automatic token refresh) is handled via httr2, which
  also caches tokens across sessions (#88).

* `mcp_tools()` now converts MCP tool-result content blocks into ellmer-native
  text and image content, allowing ellmer chats to receive image results from
  MCP tools.

**Bug fixes**:

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

- Notably, `mcp_tools()` did not gain an implementation of the HTTP transport. Instead, we now recommend the `@npx mcp-remote` tool for serving local MCP servers via the HTTP transport in the documentation.

* `mcp_tools()` now errors more informatively when an MCP server process exits unexpectedly (#82).

# mcptools 0.1.1

* Addressed an issue in tests on `r-devel-linux-x86_64-fedora-clang`.

# mcptools 0.1.0

* Initial CRAN submission.

Before the initial release of the package, mcptools was called acquaint and supplied a default set of tools from btw, currently a GitHub-only package, when R was used as an MCP server. The direction of the dependency has been reversed; to use the same functionality from before, transition `acquaint::mcp_server()` to `btw::btw_mcp_server()` and `acquaint::mcp_session()` to `btw::btw_mcp_session()`.
