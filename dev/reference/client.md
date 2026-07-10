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

`mcp_tools()` returns a list of ellmer tools that can be passed directly
to the `$set_tools()` method of an
[ellmer::Chat](https://ellmer.tidyverse.org/reference/Chat.html) object.
If the file at `config` doesn't exist, an error.

## Configuration

mcptools uses the same .json configuration file format as Claude
Desktop; most MCP servers will define example .json to configure the
server with Claude Desktop in their README files. By default, mcptools
will look to `file.path("~", ".config", "mcptools", "config.json")`; you
can edit that file with
`file.edit(file.path("~", ".config", "mcptools", "config.json"))`.

The mcptools config file should be valid .json with an entry
`mcpServers`. That entry should contain named elements, each configuring
either a local stdio server with `command` and `args`, or a remote
Streamable HTTP server with `url`. Stdio MCP server processes receive an
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

For remote Streamable HTTP MCP servers, configure a server with `url`.
Static headers can be supplied with `headers`; protocol-owned headers
such as `Accept`, `Content-Type`, `MCP-Session-Id`, and
`MCP-Protocol-Version` are managed by mcptools and cannot be configured
manually. Remote endpoints must use HTTPS; HTTP is allowed only for
loopback development servers or for explicit unsafe opt-out with
`allow_http`.

When no static `Authorization` header is configured and the server
answers an unauthenticated request with a `401` OAuth challenge,
mcptools automatically runs the OAuth authorization-code flow, opening a
browser for sign-in. Tokens are cached and refreshed, so the browser
step happens only until a cached token expires. An `oauth` block is
optional and only needed to override the defaults described below.

Remote server entries support these fields:

- `url`: the Streamable HTTP MCP endpoint.

- `headers`: named static headers. Values may use `${ENVVAR}`
  interpolation.

- `timeout`: a number of seconds for the overall HTTP request timeout.

- `allow_http`: allow credentialed non-loopback HTTP endpoints.

- `ignore_tools`: tool names or `*` wildcards to hide and block.

- `oauth`: OAuth settings.

OAuth settings may include `authorization_server`, `resource`, `scope`
with `scope_mode = "override"`, `client_info`, `manual_client_info`,
`client_metadata`, `redirect_uri` or `callback_host`/`callback_port`/
`callback_path`, `cache_dir`, and `allow_http`. mcptools supports OAuth
2.1 with PKCE: it discovers the authorization server from the
protected-resource metadata advertised in a `401` challenge, registers a
client dynamically when the server supports it, and caches tokens
(refreshing them automatically).

Remote HTTP requests use httr2 and curl. Proxy and corporate CA settings
should generally use the standard curl environment variables, such as
`HTTPS_PROXY`, `NO_PROXY`, `SSL_CERT_FILE`, and `CURL_CA_BUNDLE`. Stdio
server processes inherit these variables through mcptools' default
environment allowlist.

    {
      "mcpServers": {
        "remote-example": {
          "url": "https://remote.mcp.server/mcp",
          "timeout": 30,
          "headers": {
            "Authorization": "Bearer ${REMOTE_MCP_TOKEN}"
          }
        }
      }
    }

## See also

This function implements R as an MCP *client*. To use R as an MCP
*server*, i.e. to provide apps like Claude Desktop or Claude Code with
access to R-based tools, see
[`mcp_server()`](https://posit-dev.github.io/mcptools/dev/reference/server.md).

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
