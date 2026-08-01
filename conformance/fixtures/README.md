# Conformance tool fixtures

Every `*.R` file in this directory is `source()`d by
`conformance/everything-server.R` at launch. A fixture file must **return a list
of `ellmer::tool()` objects** (its last top-level expression). Those tools are
appended to the everything-server's tool set — no edits to the launcher needed.

```r
# conformance/fixtures/simple-text.R
list(
  ellmer::tool(
    fun = function() "MCP is awesome!",
    name = "echo",                 # optional; else derived from `fun`
    description = "Echoes a fixed string"
  )
)
```

Notes:

- The wire (tool) name ellmer sends is derived from `fun` unless you pass
  `name =` explicitly. Set `name =` to match the exact name the conformance
  scenario expects (see `conformance/reference/everything-server-contract.md`).
- To preserve a raw JSON Schema that ellmer's type system cannot express, set
  `attr(tool, "mcp_input_schema")` to a named list. `tools/list` sends that
  schema unchanged.
- Keep fixtures deterministic — conformance compares exact output.
- One file per feature area keeps parallel workspaces merge-clean.
