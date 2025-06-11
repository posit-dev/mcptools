# mcp_tools() errors informatively when file doesn't exist

    Code
      read_mcp_config("nonexistent/file/")
    Condition
      Error in `as.character()`:
      ! cannot coerce type 'closure' to vector of type 'character'

# mcp_tools() errors informatively with invalid JSON

    Code
      read_mcp_config(tmp_file)
    Condition
      Error:
      ! Configuration processing failed
      i The configuration file `path` must be valid JSON.
      Caused by error:
      ! lexical error: invalid char in json text.
                                             invalid json
                           (right here) ------^

# mcp_tools() errors informatively without mcpServers entry

    Code
      read_mcp_config(tmp_file)
    Condition
      Error:
      ! Configuration processing failed.
      i `path` must have a top-level mcpServers entry.

