## Overview

The mcptools package uses nanonext for inter-process communication between the MCP server and R sessions. nanonext provides asynchronous messaging using the nanomsg/nng protocols.

The full MCP specification lives at https://modelcontextprotocol.io/specification/latest. Read it liberally.

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

- On Linux and macOS, sessions use filesystem-based IPC sockets in a per-user
  directory (0700 permissions) for cross-user isolation
- Directory selection: `MCPTOOLS_SOCKET_DIR` > `XDG_RUNTIME_DIR/mcptools/` >
  `$TMPDIR/mcptools-<user>/` > `/tmp/mcptools-<user>/`
- On Windows, named pipes are used (`ipc://mcptools-socket{N}`)
- Socket directory permissions are enforced as 0700 (owner-only) on every access
- Filesystem sockets require explicit cleanup via `.onUnload()` and `reg.finalizer()`
- Stale socket files from crashed sessions are cleaned on `mcp_session()` and
  `mcp_server()` startup using ping-based detection (100ms timeout)
- `mcp_server()` auto-connects to the session matching its working directory;
  falls back to slot 1 when zero or multiple sessions match
- All socket address construction flows through `the$socket_url`
