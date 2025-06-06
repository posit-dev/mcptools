## Overview

The acquaint package uses nanonext for inter-process communication between the MCP server and R sessions. nanonext provides asynchronous messaging using the nanomsg/nng protocols.

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

## acquaint Architecture

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

- Sessions listen on `inproc://acquaint-session-{i}` where `i` is auto-incremented
- Server dials to `inproc://acquaint-session-1` by default
- `inproc://` transport is fast for same-machine communication
- Connections are cleaned up with `nanonext::reap()` on exit
