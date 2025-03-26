
<!-- README.md is generated from README.Rmd. Please edit that file -->

# rmcp

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![CRAN
status](https://www.r-pkg.org/badges/version/rmcp)](https://CRAN.R-project.org/package=rmcp)
<!-- badges: end -->

The goal of rmcp is to enable LLM-enabled tools like Claude Code to
learn about the R packages you have installed using the [Model Context
Protocol](https://modelcontextprotocol.io/) (MCP). Tools configured with
rmcp can peruse package documentation and learn to use R packages even
if they weren’t included in their training data.

rmcp is written primarily in TypeScript but is distributed as an R
package for ease of distribution/install for R users. Installing the
package ensures you have the needed dependencies and provides a
shortcut, `mcp_config()`, to help you configure the tool with other
applications.

> IMPORTANT: This is an early proof of concept. Use at your own risk!

## Installation

You can install the development version of rmcp like so:

``` r
pak::pak("simonpcouch/rmcp")
```

rmcp can be hooked up to any application that supports MCP. To do so,
use `mcp_config()` to generate the config for your machine:

``` r
library(rmcp)

mcp_config()
#> {
#>   "mcpServers": {
#>     "r-mcp": {
#>       "command": "node",
#>       "args": ["/Users/simoncouch/Documents/rrr/rmcp/inst/node/dist/index.js"]
#>     }
#>   }
#> }
```

Then, paste that output into the relevant configuration file for your
application. For example:

- Claude Code: `~/.config/anthropic/mcp-config.json`
- Claude for Desktop (on macOS):
  `~/Library/Application Support/Claude/claude_desktop_config.json`

## Example

<img src="../../../../../private/var/folders/6c/w21prsj167b_x82q4_s45t340000gn/T/RtmptR9xT2/temp_libpathdaed11dc5b90/rmcp/figs/rmcp.gif" alt="A screencast of a chat with Claude. I ask 'Do I have any R packages installed with the word flights in the name?' and, after searching through the documentation of my currently installed R packages, Claude mentions two that I have installed." width="100%" />
