## Overview

mcptools is an R package implementing an SDK for the Model Context Protocol. It ends "both sides" of the protocol—`mcp_server()` launches an MCP server, and `mcp_tools()` implements the client side. `mcp_session()` is an optional extension to `mcp_server()` that allows users to connect MCP servers to their active R sessions.

The mcptools package uses nanonext for inter-process communication between the MCP server and R sessions. nanonext provides asynchronous messaging using the nanomsg/nng protocols.

The full MCP specification lives at https://modelcontextprotocol.io/specification/latest. Read it liberally.
