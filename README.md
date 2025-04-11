<!-- README.md is generated from README.Rmd. Please edit that file -->

# acquaint

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![CRAN
status](https://www.r-pkg.org/badges/version/acquaint)](https://CRAN.R-project.org/package=acquaint)
[![R-CMD-check](https://github.com/simonpcouch/acquaint/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/simonpcouch/acquaint/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

The goal of acquaint is to enable LLM-enabled tools like Claude Code to
learn about the R packages you have installed using the [Model Context
Protocol](https://modelcontextprotocol.io/) (MCP). Tools configured with
acquaint can peruse package documentation and learn to use R packages even
if they weren’t included in their training data.

acquaint is written primarily in TypeScript but is distributed as an R
package for ease of distribution/install for R users. Installing the
package ensures you have the needed dependencies and provides a
shortcut, `mcp_config()`, to help you configure the tool with other
applications.

> IMPORTANT: This is an early proof of concept. Use at your own risk!

## Installation

You can install the development version of acquaint like so:

    pak::pak("simonpcouch/acquaint")

acquaint can be hooked up to any application that supports MCP. Use
`mcp_config()` to generate the config for your machine for common
applications. For example, **Claude Code**:

    library(acquaint)

    mcp_config("Claude Code")
    #> In a terminal, run:
    #> 
    #> claude mcp add -s "user" r-acquaint node /Users/simoncouch/Library/R/arm64/4.4/library/acquaint/node/dist/index.js

Or, **Claude Desktop**:

    mcp_config("Claude Desktop")
    #> Run `file.edit(~/Library/Application Support/Claude/claude_desktop_config.json)`
    #> 
    #> Then, paste the following:
    #> {
    #>   "mcpServers": {
    #>     "r-acquaint": {
    #>       "command": "node",
    #>       "args": ["/Users/simoncouch/Library/R/arm64/4.4/library/acquaint/node/dist/index.js"]
    #>     }
    #>   }
    #> }

## Example

In Claude Desktop, I’ll write the following:

> Using the R packages I have installed, write code to download data on
> flights in/out of Chicago airports in 2024.

In a typical chat interface, I’d be wary of two failure points here:

1.  The model doesn’t know which packages I have installed.
2.  If the model correctly guesses which packages I have installed,
    there may not be enough information about how to *use* the packages
    baked into its weights to write correct code.

<img src="https://github.com/user-attachments/assets/821ea3d6-4e30-46d6-ab9b-301276af2c35" alt="A screencast of a chat with Claude. I ask 'Using the R packages I have installed, write code to download data on flights in/out of Chicago airports in 2024.' and, after searching through the documentation of my currently installed R packages, Claude writes R code to do so." width="100%" />

Through first searching through my installed packages, Claude can locate
the anyflights package, which seems like a reasonable solution. The
model then discovers the package’s `anyflights()` function and reads its
documentation, and can pattern-match from there to write the correct
code.
