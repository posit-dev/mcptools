#!/usr/bin/env Rscript
# Everything-server launcher for MCP conformance testing.
#
# This boots the (forked) `mcptools` Streamable-HTTP server used as the
# system-under-test by the official MCP conformance suite
# (https://github.com/modelcontextprotocol/conformance).
#
# It currently exposes only the single upstream example tool, which reproduces
# the recorded baseline (see conformance/BASELINE.md). Feature workspaces grow
# this toward the full "everything server" contract documented in
# files/everything-server-contract.md (14 named tools, resources, prompts,
# completion, logging, elicitation, sampling, progress).
#
# Env:
#   MCP_HOST  bind host (default 127.0.0.1)
#   MCP_PORT  bind port (default 3001)

suppressPackageStartupMessages({
  library(mcptools)
  library(ellmer)
})

host <- Sys.getenv("MCP_HOST", "127.0.0.1")
port <- as.integer(Sys.getenv("MCP_PORT", "3001"))

# ---- Tool fixtures ---------------------------------------------------------
# Baseline fixture: a single deterministic tool. The wire name is derived by
# ellmer from `fun` (=> "rnorm"), NOT the list element name.
base_tools <- list(
  ellmer::tool(
    fun = rnorm,
    description = "Draw numbers from a random normal distribution",
    arguments = list(
      n = ellmer::type_integer(
        "The number of observations. Must be a positive integer."
      ),
      mean = ellmer::type_number("The mean value of the distribution."),
      sd = ellmer::type_number(
        "The standard deviation of the distribution. Must be a non-negative number."
      )
    )
  )
)

# Additive fixtures: each conformance/fixtures/*.R file is sourced and may
# return a list of ellmer tools, which are appended here. Feature workspaces
# add their tools by dropping in a new fixture file (no edits to this launcher).
fixtures_dir <- file.path(
  dirname(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])),
  "fixtures"
)
extra_tools <- list()
if (dir.exists(fixtures_dir)) {
  for (f in sort(list.files(fixtures_dir, pattern = "\\.R$", full.names = TRUE))) {
    val <- tryCatch(source(f, local = TRUE)$value, error = function(e) {
      message(sprintf("[everything-server] fixture %s failed: %s", basename(f), conditionMessage(e)))
      NULL
    })
    if (is.list(val)) {
      extra_tools <- c(extra_tools, val)
    }
  }
}

tools <- c(base_tools, extra_tools)

message(sprintf(
  "[everything-server] mcptools %s -> http://%s:%d/mcp",
  as.character(utils::packageVersion("mcptools")), host, port
))

mcptools::mcp_server(
  tools = tools,
  type = "http",
  host = host,
  port = port,
  session_tools = FALSE
)
