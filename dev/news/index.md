# Changelog

## mcptools (development version)

Only an internal testing change that addresses a temp directory cleanup
NOTE.

## mcptools 1.0.1

CRAN release: 2026-07-27

This release includes several security-oriented fixes, in addition to a
couple quality of life improvements for multi-user and multi-session
workspaces:

- The server now chooses its R session at tool-call time rather than
  always connecting to the first session: it prefers the session whose
  working directory matches its own (clients like Claude Code and Posit
  Assistant launch the server in the project directory), falling back to
  the only running session. When several sessions are running and none
  matches, tools execute in the server’s own R process until the client
  calls `select_r_session`. Previously, a second client + session pair
  in another project window would silently execute tools in the first
  project’s session
  ([\#114](https://github.com/posit-dev/mcptools/issues/114)).

- Sessions now use per-user filesystem IPC sockets in an
  owner-only (0700) directory instead of a shared address. On multi-user
  Linux hosts (e.g. Posit Workbench) the previous default let any local
  user connect to another user’s
  [`mcp_session()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  and execute tools in it; sessions are now isolated by Unix user. The
  socket directory follows `MCPTOOLS_SOCKET_DIR` \>
  `XDG_RUNTIME_DIR/mcptools/` \> `$TMPDIR/mcptools-<user>/` \>
  `/tmp/mcptools-<user>/`
  ([@kwbyron-lilly](https://github.com/kwbyron-lilly),
  [\#114](https://github.com/posit-dev/mcptools/issues/114)).

- The session and server now authenticate every IPC message with a
  per-user secret stored alongside the sockets, so a session acts only
  on tool calls from the paired server and the server accepts only
  responses from a genuine session.

- Tools returning
  [`ellmer::content_image_url()`](https://ellmer.tidyverse.org/reference/content_image_url.html)
  inline the image by fetching it server-side; that fetch is now
  restricted to `http`/`https` URLs, and any redirects are followed by
  mcptools itself so each hop is re-checked rather than trusted to curl.
  When the server is reached over the network (an HTTP deployment), the
  fetch additionally refuses private, loopback, and link-local
  addresses, so a tool argument cannot steer it at cloud-metadata
  endpoints, internal hosts, or local files. Local (stdio) servers keep
  fetching addresses on their own machine.

- Socket files left behind by a crashed session are now reclaimed
  automatically: the next session that needs the slot detects the dead
  file and reuses it.

- `list_r_sessions()` no longer returns spurious `"5"` entries when a
  session is slow to respond to discovery probes.

- [`mcp_tools()`](https://posit-dev.github.io/mcptools/dev/reference/client.md)
  now initiates the MCP OAuth authorization-code flow automatically when
  a remote server configured with only a `url` answers an
  unauthenticated request with a `401` challenge. Previously, connecting
  to such a server required either a static `Authorization` header or an
  explicit `oauth` block; the `oauth` block is now needed only to
  override defaults.

## mcptools 1.0.0

CRAN release: 2026-07-02

### `mcp_server()`

**New features**:

- mcptools can now run as a Posit Connect R API engine. Add a
  `_server.yml` with `engine: mcptools`, point `tools` to an `.R` file
  returning
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  objects, and deploy with
  `rsconnect::deployAPI(".", contentCategory = "mcp")`.

- [`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  can now return inline image content from tools that produce
  [`ellmer::ContentImageInline`](https://ellmer.tidyverse.org/reference/Content.html)
  results, including mixed text and image content
  ([\#96](https://github.com/posit-dev/mcptools/issues/96),
  [\#102](https://github.com/posit-dev/mcptools/issues/102)).

- [`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  now returns `structuredContent` alongside serialized JSON text for
  successful tool results that are naturally represented as JSON
  objects, when using MCP protocol version 2025-06-18 or later
  ([\#104](https://github.com/posit-dev/mcptools/issues/104)).

- [`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  now includes ellmer tool annotations in `tools/list` responses,
  preserving MCP safety hints such as `title`, `readOnlyHint`,
  `destructiveHint`, `idempotentHint`, and `openWorldHint`
  ([\#100](https://github.com/posit-dev/mcptools/issues/100),
  [\#105](https://github.com/posit-dev/mcptools/issues/105)).

**Bug fixes**:

- HTTP
  [`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  requests now honor the `MCP-Protocol-Version` header, return
  `400 Bad Request` for unsupported protocol versions, and no longer let
  protocol negotiation from one HTTP client shape responses for another.

- JSON output now serializes R `NULL` values as JSON `null`, fixing
  JSON-RPC responses with null request IDs.

- [`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  no longer falls through after reporting `Invalid Request` for invalid
  stdio client messages.

- Forwarded
  [`mcp_session()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  tool calls now return JSON-RPC errors when the selected R session does
  not respond within two minutes, rather than hanging indefinitely.
  Configure the timeout with the
  `mcptools.session_response_timeout_seconds` option or the
  `MCPTOOLS_SESSION_RESPONSE_TIMEOUT_SECONDS` environment variable.
  Session receive errors are also logged instead of silently discarded
  ([\#98](https://github.com/posit-dev/mcptools/issues/98)).

### `mcp_tools()`

**New features**:

- [`mcp_tools()`](https://posit-dev.github.io/mcptools/dev/reference/client.md)
  can now connect directly to remote Streamable HTTP MCP servers,
  configured with `url` instead of `command`. Static `headers` are
  supported for token auth, and full OAuth 2.1 (authorization-server
  discovery, Dynamic Client Registration, PKCE, and automatic token
  refresh) is handled via httr2, which also caches tokens across
  sessions ([\#88](https://github.com/posit-dev/mcptools/issues/88)).

- [`mcp_tools()`](https://posit-dev.github.io/mcptools/dev/reference/client.md)
  now converts MCP tool-result content blocks into ellmer-native text
  and image content, allowing ellmer chats to receive image results from
  MCP tools.

**Bug fixes**:

- [`mcp_tools()`](https://posit-dev.github.io/mcptools/dev/reference/client.md)
  now launches MCP server processes with an allowlisted environment plus
  configured `env` variables. Previously, servers without configured
  `env` inherited the full R process environment, while servers with
  configured `env` received only those variables. The new behavior more
  closely matches reference MCP SDKs, reduces accidental credential
  exposure, and fixes Windows startup failures when `env` is configured.
  Servers that need additional non-allowlisted variables should list
  them in `env`
  ([\#62](https://github.com/posit-dev/mcptools/issues/62)).

## mcptools 0.2.1

CRAN release: 2026-03-17

- [`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  now ensures that `inputSchema` always includes a `properties` field,
  even for tools with no arguments
  ([\#91](https://github.com/posit-dev/mcptools/issues/91) by
  [@itkonen](https://github.com/itkonen)).

- [`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  now negotiates the protocol version with clients, supporting versions
  2024-11-05 through 2025-11-25
  ([\#92](https://github.com/posit-dev/mcptools/issues/92) by
  [@itkonen](https://github.com/itkonen)).

## mcptools 0.2.0

CRAN release: 2025-10-29

### Server

- [`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  now supports HTTP transport in addition to stdio. Use `type = "http"`
  to start an HTTP server, with optional `host` and `port` arguments.
  For now, the implementation is authless.

- [`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  now formats tool results in the same way as ellmer
  ([\#78](https://github.com/posit-dev/mcptools/issues/78) by
  [@gadenbuie](https://github.com/gadenbuie)).

- [`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  gains logical argument `session_tools`, allowing users to opt-out of
  presenting R session tools (that make it possible to communicate with
  [`mcp_session()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)s)
  to clients.

- Several tightenings-up of the implementation:

  - JSON-RPC responses now retain an explicit `id = NULL` value,
    ensuring parse-error replies conform to the MCP specification.
  - [`mcp_tools()`](https://posit-dev.github.io/mcptools/dev/reference/client.md)
    now sends and receives a `"notifications/initialized"`
    ([\#77](https://github.com/posit-dev/mcptools/issues/77) by
    [@galachad](https://github.com/galachad)).
  - The implementation now supports the 2025-06-18 protocol version,
    updated from 2024-11-05.

- [`mcp_session()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
  now invisibly returns the nanonext socket used for communicating with
  the server.

### Client

- Notably,
  [`mcp_tools()`](https://posit-dev.github.io/mcptools/dev/reference/client.md)
  did not gain an implementation of the HTTP transport. Instead, we now
  recommend the `@npx mcp-remote` tool for serving local MCP servers via
  the HTTP transport in the documentation.

- [`mcp_tools()`](https://posit-dev.github.io/mcptools/dev/reference/client.md)
  now errors more informatively when an MCP server process exits
  unexpectedly
  ([\#82](https://github.com/posit-dev/mcptools/issues/82)).

## mcptools 0.1.1

CRAN release: 2025-09-08

- Addressed an issue in tests on `r-devel-linux-x86_64-fedora-clang`.

## mcptools 0.1.0

CRAN release: 2025-07-18

- Initial CRAN submission.

Before the initial release of the package, mcptools was called acquaint
and supplied a default set of tools from btw, currently a GitHub-only
package, when R was used as an MCP server. The direction of the
dependency has been reversed; to use the same functionality from before,
transition `acquaint::mcp_server()` to `btw::btw_mcp_server()` and
`acquaint::mcp_session()` to `btw::btw_mcp_session()`.
