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

    pak::pak("simonpcouch/rmcp")

rmcp can be hooked up to any application that supports MCP. Use
`mcp_config()` to generate the config for your machine for common
applications. For example, **Claude Code**:

    library(rmcp)

    mcp_config("Claude Code")
    #> In a terminal, run:
    #> 
    #> claude mcp add -s "user" r-mcp node /Users/simoncouch/Library/R/arm64/4.4/library/rmcp/node/dist/index.js

Or, **Claude Desktop**:

    mcp_config("Claude Desktop")
    #> Run `file.edit(~/Library/Application Support/Claude/claude_desktop_config.json)`
    #> 
    #> Then, paste the following:
    #> {
    #>   "mcpServers": {
    #>     "r-mcp": {
    #>       "command": "node",
    #>       "args": ["/Users/simoncouch/Library/R/arm64/4.4/library/rmcp/node/dist/index.js"]
    #>     }
    #>   }
    #> }

## Example

<img src="https://github.com/user-attachments/assets/8cefbc28-f046-4dfa-af63-b8eb85bb16b0" alt="A screencast of a chat with Claude. I ask 'Do I have any R packages installed with the word flights in the name?' and, after searching through the documentation of my currently installed R packages, Claude mentions two that I have installed." width="100%" />
