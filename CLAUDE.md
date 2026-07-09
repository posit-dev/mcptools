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

- On Linux and macOS, sessions use filesystem IPC sockets in a per-user,
  owner-only (0700) directory for cross-user isolation. Directory selection:
  `MCPTOOLS_SOCKET_DIR` > `XDG_RUNTIME_DIR/mcptools/` > `$TMPDIR/mcptools-<user>/`
  > `/tmp/mcptools-<user>/`.
- On Windows, per-user named pipes are used (`ipc://mcptools-<user>-socket{N}`).
  Named pipes share a global namespace, so Windows is not a security boundary.
- `socket_dir()` is pure; the directory is created and its trust verified by
  `ensure_socket_dir()` at first socket use (from `mcp_session()`/`mcp_server()`),
  not at package load. `ensure_socket_dir()` aborts if an existing directory is a
  symlink or is owned by another uid, and tightens perms to 0700 otherwise.
- All socket address construction flows through `the$socket_url`, computed once
  in `.onLoad()`, so `MCPTOOLS_SOCKET_DIR` must be set before the package loads.
- Sessions claim the lowest free slot. When `listen()` fails on a slot,
  `reclaim_stale_socket()` does one synchronous dial: a live listener accepts a
  pipe even while its R process is busy, so a refused dial identifies a crashed
  session's leftover file, which is unlinked and the slot relisted. This means
  the server and `list_r_sessions()` need no cleanup pass of their own, and there
  are no ping-based liveness probes.
- Own-socket cleanup on clean exit runs via `.onUnload()` and
  `reg.finalizer(onexit = TRUE)`.
