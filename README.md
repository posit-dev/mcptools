
<!-- README.md is generated from README.Rmd. Please edit that file -->

# acquaint <a href="https://simonpcouch.github.io/acquaint/"><img src="man/figures/logo.png" align="right" height="240" alt="A hexagonal logo showing a sparse, forested path opening up into a well-trodden meadow path." /></a>

<!-- badges: start -->

[![Lifecycle:
experimental](https://img.shields.io/badge/lifecycle-experimental-orange.svg)](https://lifecycle.r-lib.org/articles/stages.html#experimental)
[![CRAN
status](https://www.r-pkg.org/badges/version/acquaint)](https://CRAN.R-project.org/package=acquaint)
[![R-CMD-check](https://github.com/simonpcouch/acquaint/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/simonpcouch/acquaint/actions/workflows/R-CMD-check.yaml)
<!-- badges: end -->

acquaint implements a [Model Context
Protocol](https://modelcontextprotocol.io/) (MCP) for your R session.
When configured with acquaint, tools like Claude Desktop and Claude Code
can:

- Peruse the documentation of packages you have installed,
- Check out the objects in your global environment, and
- Retrieve metadata about your session and platform.

> IMPORTANT: This is an early proof of concept. Use at your own risk!

## Installation

You can install the development version of acquaint like so:

``` r
pak::pak("simonpcouch/acquaint")
```

acquaint can be hooked up to any application that supports MCP. For
example, to use with Claude Desktop, you might paste the following in
your Claude Desktop configuration (on macOS, at
`~/Library/Application Support/Claude/claude_desktop_config.json`):

``` json
{
  "mcpServers": {
    "r-acquaint": {
      "command": "Rscript",
      "args": ["-e", "acquaint::mcp_server()"]
    }
  }
}
```

Or, to use with Claude Code, you might type in a terminal:

``` bash
claude mcp add -s "user" r-acquaint Rscript -e "acquaint::mcp_server()"
```

Then, in your R session, call `acquaint::mcp_session()`.

For a more thorough introduction, see the vignette “Getting started with
acquaint” with `vignette("acquaint", package = "acquaint")`.

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
