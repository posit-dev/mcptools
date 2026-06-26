# NA

## Overview

The mcptools package uses nanonext for inter-process communication
between the MCP server and R sessions. nanonext provides asynchronous
messaging using the nanomsg/nng protocols.

The full MCP specification lives at
<https://modelcontextprotocol.io/specification/latest>. Read it
liberally.

## Key Concepts

### Asynchronous I/O (Aio)

- `send_aio()` and `recv_aio()` return immediately without blocking
- Operations complete asynchronously in the background
- Use `unresolved(aio)` to check if an operation is still pending
- Access results via `aio$data` (recv) or `aio$result` (send)

### Sockets and Communication Patterns

- **poly protocol**: Allows multiple connections to the same socket
- **dial/listen**: Client dials to connect, server listens for
  connections
- **pipe IDs**: poly sockets can multiplex multiple conversations

## mcptools Architecture

### Server Process

The MCP server
([`mcp_server()`](https://posit-dev.github.io/mcptools/reference/server.md))
runs in its own R process and: 1. Listens on stdin for MCP client
requests 2. Maintains a socket connection to R sessions 3. Routes tool
calls between client and sessions

### Session Processes

Interactive R sessions
([`mcp_session()`](https://posit-dev.github.io/mcptools/reference/server.md))
connect to the server and: 1. Listen for tool execution requests from
the server 2. Execute tools and send results back 3. Each session gets a
unique ID and socket connection

### Message Flow

    MCP Client → Server (stdin) → Session (socket) → Server → Client (stdout)

## Server Loop Implementation

The server uses a condition variable (`cv`) to coordinate multiple async
operations.

## Socket URLs and Connection Management

- The base socket URL is OS-derived in `.onLoad()`:
  `abstract://mcptools-socket` on Linux, `ipc://mcptools-socket` on
  Windows, `ipc:///tmp/mcptools-socket` otherwise
- Sessions listen on `{socket_url}{i}` where `i` is auto-incremented
- Server dials to `{socket_url}1` by default
- Connections are cleaned up with
  [`nanonext::reap()`](https://nanonext.r-lib.org/reference/reap.html)
  on exit
