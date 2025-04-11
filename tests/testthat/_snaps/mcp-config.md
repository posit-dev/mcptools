# mcp_config produces correct Claude Code output

    Code
      mcp_config("Claude Code")
    Output
      In a terminal, run:
      
      claude mcp add -s "user" r-acquaint node node/dist/index.js

# mcp_config produces correct Claude Desktop output for macOS

    Code
      mcp_config("Claude Desktop")
    Output
      Run `file.edit("~/Library/Application Support/Claude/claude_desktop_config.json")`
      
      Then, paste the following:
      {
        "mcpServers": {
          "r-acquaint": {
            "command": "node",
            "args": ["node/dist/index.js"]
          }
        }
      }

# mcp_config produces correct Claude Desktop output for Windows

    Code
      mcp_config("Claude Desktop")
    Output
      Run `file.edit("%APPDATA%\Claude\claude_desktop_config.json")`
      
      Then, paste the following:
      {
        "mcpServers": {
          "r-acquaint": {
            "command": "node",
            "args": ["node/dist/index.js"]
          }
        }
      }

# mcp_config errors correctly for Linux with Claude Desktop

    Code
      mcp_config("Claude Desktop")
    Condition
      Error in `mcp_config_claude_desktop()`:
      ! Claude Desktop isn't available on Linux.

