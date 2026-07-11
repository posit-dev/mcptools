# NA

## Overview

mcptools is an R package implementing an SDK for the Model Context
Protocol. It ends “both sides” of the
protocol—[`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
launches an MCP server, and
[`mcp_tools()`](https://posit-dev.github.io/mcptools/dev/reference/client.md)
implements the client side.
[`mcp_session()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
is an optional extension to
[`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md)
that allows users to connect MCP servers to their active R sessions.

The mcptools package uses nanonext for inter-process communication
between the MCP server and R sessions. nanonext provides asynchronous
messaging using the nanomsg/nng protocols.

The full MCP specification lives at
<https://modelcontextprotocol.io/specification/latest>. Read it
liberally.
