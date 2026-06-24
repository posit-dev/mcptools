# R as a client: Define ellmer tools from MCP servers

These functions implement R as an MCP *client*, so that ellmer chats can
register functionality from third-party MCP servers such as those listed
here: <https://github.com/modelcontextprotocol/servers>.

`mcp_tools()` fetches tools from MCP servers configured in the mcptools
server config file and converts them to a list of tools compatible with
the `$set_tools()` method of
[ellmer::Chat](https://ellmer.tidyverse.org/reference/Chat.html)
objects.

## Usage

``` r
mcp_tools(config = NULL)
```

## Arguments

- config:

  A single string indicating the path to the mcptools MCP servers
  configuration file. If one is not supplied, mcptools will look for one
  at the file path configured with the option `.mcptools_config`,
  falling back to
  `file.path("~", ".config", "mcptools", "config.json")`.

## Value

- `mcp_tools()` returns a list of ellmer tools that can be passed
  directly to the `$set_tools()` method of an
  [ellmer::Chat](https://ellmer.tidyverse.org/reference/Chat.html)
  object. If the file at `config` doesn't exist, an error.

## Configuration

mcptools uses the same .json configuration file format as Claude
Desktop; most MCP servers will define example .json to configure the
server with Claude Desktop in their README files. By default, mcptools
will look to `file.path("~", ".config", "mcptools", "config.json")`; you
can edit that file with
`file.edit(file.path("~", ".config", "mcptools", "config.json"))`.

The mcptools config file should be valid .json with an entry
`mcpServers`. That entry should contain named elements, each with at
least a `command` and `args` entry. MCP server processes receive an
allowlisted environment inherited from the current R process, plus any
variables configured in `env`. Configured `env` variables override
inherited variables with the same name. Servers that need additional
environment variables should list them in `env`.

For example, to configure `mcp_tools()` with GitHub's official MCP
Server <https://github.com/github/github-mcp-server>, you could write
the following in that file:

    {
      "mcpServers": {
        "github": {
          "command": "docker",
          "args": [
            "run",
            "-i",
            "--rm",
            "-e",
            "GITHUB_PERSONAL_ACCESS_TOKEN",
            "ghcr.io/github/github-mcp-server"
          ],
          "env": {
            "GITHUB_PERSONAL_ACCESS_TOKEN": "<add_your_github_pat_here>"
          }
        }
      }
    }

## Connecting to remote (http) servers

`mcp_tools()`, which supports using R as an MCP *client* via ellmer,
only implements the local (stdio) protocol. However, some MCP *servers*
only implement the http protocol.

In that case, we recommend using
[mcp-remote](https://www.npmjs.com/package/mcp-remote), a local (stdio)
MCP server that supports connecting to remote (http) servers using the
stdio protocol, with fully-featured authentication. In other words,
`mcp-remote` converts remote MCP servers to mcptools-compatible local
ones.

To connect to remote (http) MCP servers when using ellmer as a client,
use the command `npx` with the args `mcp-remote` and the URL provided by
the remote server. For example, you might write:

    {
      "mcpServers": {
        "remote-example": {
          "command": "npx",
          "args": [
            "mcp-remote",
            "https://remote.mcp.server/sse"
          ]
        }
      }
    }

mcp-remote's [homepage](https://www.npmjs.com/package/mcp-remote) has
many examples for various authentication schemes.

## See also

This function implements R as an MCP *client*. To use R as an MCP
*server*, i.e. to provide apps like Claude Desktop or Claude Code with
access to R-based tools, see
[`mcp_server()`](https://posit-dev.github.io/mcptools/reference/server.md).

## Examples

``` r
# setup
config_file <- tempfile(fileext = "json")
file.create(config_file)
#> [1] TRUE

# usually, `config` would be a persistent, user-level
# configuration file for a set of MCP server
mcp_tools(config = config_file)
#> list()

# teardown
file.remove(config_file)
#> [1] TRUE

```
