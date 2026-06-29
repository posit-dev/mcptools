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
      x Error: intentional error. Execution halted. Ran 2/2 deferred expressions

# resolve_headers() handles NULL and errors on unset vars

    Code
      resolve_env_vars("Key ${MCPTOOLS_DEFINITELY_UNSET}")
    Condition
      Error:
      ! The environment variable `MCPTOOLS_DEFINITELY_UNSET` is not set.
      i It's referenced in the headers of an MCP server config.

