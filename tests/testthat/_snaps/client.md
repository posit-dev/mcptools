# mcp_tools() errors informatively when file doesn't exist

    Code
      mcp_tools("nonexistent/file/")
    Condition
      Error in `mcp_tools()`:
      ! The acquaint MCP client configuration file does not exist.
      i Supply a non-NULL file `path` or create a file at the default configuration location '~/.config/acquaint/config.json'.

# mcp_tools() errors informatively with invalid JSON

    Code
      mcp_tools(tmp_file)
    Condition
      Error in `mcp_tools()`:
      ! Configuration processing failed
      i The configuration file `path` must be valid JSON.
      Caused by error:
      ! lexical error: invalid char in json text.
                                             invalid json
                           (right here) ------^

# mcp_tools() errors informatively without mcpServers entry

    Code
      mcp_tools(tmp_file)
    Condition
      Error in `mcp_tools()`:
      ! Configuration processing failed.
      i `path` must have a top-level mcpServers entry.

