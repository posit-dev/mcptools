
<!-- README.md is generated from README.Rmd. Please edit that file -->

# mcptools <a href="https://simonpcouch.github.io/mcptools/"><img src="man/figures/logo.png" align="right" height="240" alt="A hexagonal logo showing a sparse, forested path opening up into a well-trodden meadow path." /></a>

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![CRAN
status](https://www.r-pkg.org/badges/version/mcptools)](https://CRAN.R-project.org/package=mcptools)
[![R-CMD-check](https://github.com/posit-dev/mcptools/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/posit-dev/mcptools/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

mcptools implements the [Model Context
Protocol](https://modelcontextprotocol.io/) in R. There are two sides to
mcptools:

- **R as an MCP server**: When configured with mcptools, MCP-enabled
  tools like Claude Desktop, Claude Code, and VS Code GitHub Copilot can
  run R code *in the sessions you have running* to answer your
  questions. While the package supports configuring arbitrary R
  functions, you may be interested in the
  [btw](https://posit-dev.github.io/btw/) package’s integrated support
  for mcptools, which provides a default set of tools to to peruse the
  documentation of packages you have installed, check out the objects in
  your global environment, and retrieve metadata about your session and
  platform.
- **R as an MCP client**: Register third-party MCP servers with ellmer
  chats to integrate additional context into
  e.g. [shinychat](https://github.com/posit-dev/shinychat) and
  [querychat](https://posit-dev.github.io/querychat/) apps.

> IMPORTANT: This package is highly experimental and its interface may
> change rapidly!
>
> This package used to be called acquaint and supplied a default set of
> tools from [btw](https://github.com/posit-dev/btw) when R was used as
> an MCP server. The direction of the dependency has been reversed; to
> use the same functionality from before, transition
> `acquaint::mcp_server()` to `btw::btw_mcp_server()` and
> `acquaint::mcp_session()` to `btw::btw_mcp_session()`.

## Installation

You can install the development version of mcptools like so:

``` r
pak::pak("posit-dev/mcptools")
```

### R as an MCP server

mcptools can be hooked up to any application that supports MCP. For
example, to use with Claude Desktop, you might paste the following in
your Claude Desktop configuration (on macOS, at
`~/Library/Application Support/Claude/claude_desktop_config.json`):

``` json
{
  "mcpServers": {
    "r-mcptools": {
      "command": "Rscript",
      "args": ["-e", "mcptools::mcp_server()"]
    }
  }
}
```

Or, to use with Claude Code, you might type in a terminal:

``` bash
claude mcp add -s "user" r-mcptools -- Rscript -e "mcptools::mcp_server()"
```

Then, if you’d like models to access variables in specific R sessions,
call `mcptools::mcp_session()` in those sessions. (You might include a
call to this function in your .Rprofile, perhaps using
`usethis::edit_r_profile()`, to automatically register every session you
start up.)

### R as an MCP client

mcptools uses the Claude Desktop configuration file format to register
third-party MCP servers, as most MCP servers provide setup instructions
for Claude Desktop in their documentation. For example, here’s what the
[official GitHub MCP
server](https://github.com/github/github-mcp-server) configuration would
look like:

``` json
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
        "GITHUB_PERSONAL_ACCESS_TOKEN": "<YOUR_TOKEN>"
      }
    }
  }
}
```

Once the configuration file has been created (by default, mcptools will
look to `file.path("~", ".config", "mcptools", "config.json")`),
`mcp_tools()` will return a list of ellmer tools which you can pass
directly to the `$set_tools()` method from ellmer:

    ch <- ellmer::chat_anthropic()
    ch$set_tools(mcp_tools())

    ch$chat("What issues are open on posit-dev/mcptools?")

## Example

In Claude Desktop, I’ll write the following:

> Using the R packages I have installed, write code to download data on
> flights in/out of Chicago airports in 2024.

In a typical chat interface, I’d be wary of two failure points here:

1)  The model doesn’t know which packages I have installed.
2)  If the model correctly guesses which packages I have installed,
    there may not be enough information about how to *use* the packages
    baked into its weights to write correct code.

<img src="https://github.com/user-attachments/assets/821ea3d6-4e30-46d6-ab9b-301276af2c35" alt="A screencast of a chat with Claude. I ask 'Using the R packages I have installed, write code to download data on flights in/out of Chicago airports in 2024.' and, after searching through the documentation of my currently installed R packages, Claude writes R code to do so." width="100%" />

Through first searching through my installed packages, Claude can locate
the anyflights package, which seems like a reasonable solution. The
model then discovers the package’s `anyflights()` function and reads its
documentation, and can pattern-match from there to write the correct
code.
