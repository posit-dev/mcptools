## Overview

The mcptools package uses nanonext for inter-process communication between the MCP server and R sessions. nanonext provides asynchronous messaging using the nanomsg/nng protocols.

The full plain-text MCP specification lives in `.md` files in `inst/spec/`—tool call for it as needed.

## Key Concepts

### Asynchronous I/O (Aio)
- `send_aio()` and `recv_aio()` return immediately without blocking
- Operations complete asynchronously in the background
- Use `unresolved(aio)` to check if an operation is still pending
- Access results via `aio$data` (recv) or `aio$result` (send)

### Sockets and Communication Patterns
- **poly protocol**: Allows multiple connections to the same socket
- **dial/listen**: Client dials to connect, server listens for connections
- **pipe IDs**: poly sockets can multiplex multiple conversations

## mcptools Architecture

### Server Process
The MCP server (`mcp_server()`) runs in its own R process and:
1. Listens on stdin for MCP client requests
2. Maintains a socket connection to R sessions
3. Routes tool calls between client and sessions

### Session Processes  
Interactive R sessions (`mcp_session()`) connect to the server and:
1. Listen for tool execution requests from the server
2. Execute tools and send results back
3. Each session gets a unique ID and socket connection

### Message Flow
```
MCP Client → Server (stdin) → Session (socket) → Server → Client (stdout)
```

## Server Loop Implementation

The server uses a condition variable (`cv`) to coordinate multiple async operations.

## Socket URLs and Connection Management

- Sessions listen on `inproc://mcptools-session-{i}` where `i` is auto-incremented
- Server dials to `inproc://mcptools-session-1` by default
- `inproc://` transport is fast for same-machine communication
- Connections are cleaned up with `nanonext::reap()` on exit

## HTTP Transport Implementation

### Current Status

The HTTP transport implementation follows the "MUSTs only" principle from the MCP specification:

**Implemented (MUSTs):**
- HTTP POST endpoint for JSON-RPC messages
- `MCP-Protocol-Version` header validation
- Origin validation for DNS rebinding protection
- Client-side session ID tracking (if server provides `Mcp-Session-Id` header)
- GET endpoint (returns 405 - SSE streaming not implemented)

**Not Implemented (MAYs/SHOULDs):**
- Server-side session management (MAY in spec)
- SSE streaming for GET requests (optional)
- OAuth 2.1 authentication (OPTIONAL in spec)
- HTTPS/TLS support

### HTTP vs HTTPS

**Protocol Requirements:**
- The MCP protocol does NOT require HTTPS for authless HTTP servers
- HTTPS is only REQUIRED for OAuth/authorization endpoints (which we don't implement)

**Client Compatibility:**
- **Claude Code**: Works with `http://` servers ✓
- **Claude Desktop**: Requires `https://` servers (product policy, not protocol requirement) ✗

Since HTTPS requires SSL certificates (self-signed for local dev, proper certs for production),
we defer HTTPS support until OAuth 2.1 is implemented, when it becomes a MUST.

### Testing with the Inspector

The MCP inspector helps test MCP servers:

```bash
Rscript -e "mcptools::mcp_server(type = 'http', port = 9000)"
```

Then:

```bash
npx @modelcontextprotocol/inspector --transport http --server-url http://127.0.0.1:9000
```

### Using with Claude Code

Add the HTTP server to Claude Code:

```bash
claude mcp add --transport http r-mcptools-http http://127.0.0.1:9000
```

Remove it:

```bash
claude mcp remove r-mcptools-http
```
