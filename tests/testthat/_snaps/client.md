# mcp_tools() errors informatively when file doesn't exist

    Code
      mcp_tools("nonexistent/file/")
    Condition
      Error in `mcp_tools()`:
      ! The mcptools MCP client configuration file does not exist.
      i Supply a non-NULL file `config` or create a file at the default configuration location '~/.config/mcptools/config.json'.

# mcp_tools() errors informatively with invalid JSON

    Code
      mcp_tools(tmp_file)
    Condition
      Error in `mcp_tools()`:
      ! Configuration processing failed
      i The configuration file `config` must be valid JSON.
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
      i `config` must have a top-level mcpServers entry.

# mcp_tools() errors informatively when process exits

    Code
      mcp_tools(tmpfile)
    Condition
      Error in `mcp_tools()`:
      ! The command `Rscript` failed with the following error:
      x Error: intentional error. Execution halted

# config capabilities must be an object

    Code
      mcp_config_capabilities(list("a", "b"))
    Condition
      Error:
      ! MCP server configuration failed.
      i capabilities must be a JSON object.

