# Feature-authoring guide (conformance-first, merge-clean)

This repo is a **fork-and-elevate** of Posit's `mcptools`, driven by the official
[MCP conformance suite](https://github.com/modelcontextprotocol/conformance). The
goal is to take the current spec (**2025-11-25**) fully green, then add the
**2026-07-28** GA lifecycle + cross-version support.

Work happens in **parallel feature workspaces**, each branched off the
`conformance-foundation` branch and merged back. The foundation is designed so
that adding a feature touches **only new files**, keeping merges conflict-free.

## The additive registry (why merges don't collide)

The central request dispatchers in `R/server.R` are frozen. Instead of editing
them, a feature registers handlers + capabilities through
`R/mcp-registry.R`:

- `register_mcp_method(method, handler)` — handle a JSON-RPC method.
- `register_mcp_capability(fragment)` — merge a fragment into the advertised
  `capabilities` map (e.g. `list(resources = named_list(subscribe = TRUE))`).

All registration runs from a **registrar** you name `.register_mcp_<feature>()`.
`.onLoad()` auto-discovers every `.register_mcp_*` in the namespace and runs it —
so a feature is a **new file only**.

### Handler contract

```r
handler <- function(data, protocol_version, transport) { ... }
```

- `data` — parsed JSON-RPC request/notification (an R list).
- `protocol_version` — negotiated version string (e.g. `"2025-11-25"`).
- `transport` — `"http"` or `"stdio"`.
- Return value for a **request** (`data$id` present):
  - a `list` → sent as the JSON-RPC `result`.
  - `jsonrpc_error(code, message, data = NULL)` → sent as the JSON-RPC `error`.
- Return value for a **notification** (`data$id` absent) is ignored.

Useful internal helpers: `named_list()` (forces `{}` not `[]` when empty),
`drop_nulls()`, `jsonrpc_response()`, `%||%`, and the `the` package env.

## Anatomy of a feature file

```r
# R/mcp-resources.R
.mcp_resources_list <- function(data, protocol_version, transport) {
  list(resources = list(
    list(uri = "file:///example.txt", name = "example", mimeType = "text/plain")
  ))
}

.mcp_resources_read <- function(data, protocol_version, transport) {
  uri <- data$params$uri
  if (!identical(uri, "file:///example.txt")) {
    return(jsonrpc_error(-32602, paste("Unknown resource:", uri)))
  }
  list(contents = list(
    list(uri = uri, mimeType = "text/plain", text = "hello")
  ))
}

# Registrar — auto-discovered by .onLoad(). MUST be named .register_mcp_<feature>.
.register_mcp_resources <- function() {
  register_mcp_method("resources/list", .mcp_resources_list)
  register_mcp_method("resources/read", .mcp_resources_read)
  register_mcp_capability(list(resources = named_list(
    subscribe = FALSE, listChanged = FALSE
  )))
}
```

If your feature needs **tools** (e.g. tool content-type scenarios), add a
fixture file under `conformance/fixtures/` (see that dir's README) instead of
editing the launcher.

## Workflow for a feature workspace

1. Branch off `conformance-foundation`.
2. Read the exact contract for your scenarios:
   - `conformance/reference/everything-server-contract.md` — per-scenario tool
     names, magic values, resource/prompt payloads, schemas.
   - `conformance/reference/sep-implementation-guide.md` — SEP numbers,
     JSON-RPC shapes, reference-SDK PRs, gotchas, dependency graph.
3. Add `R/mcp-<feature>.R` (+ any `conformance/fixtures/*.R`).
4. `R CMD INSTALL --no-docs --no-multiarch .`
5. Remove the scenarios you now satisfy from
   `conformance/expected-failures.yml`.
6. `make conformance` — it must exit 0. The evaluator fails on **unexpected
   passes** too, so you must delete every entry you turn green (this is the
   ratchet).
7. Merge back into `conformance-foundation`.

## Local iteration without the full suite

```r
R CMD INSTALL --no-docs --no-multiarch .
Rscript -e '
  ns <- getNamespace("mcptools"); g <- function(x) get(x, ns)
  print(g("dispatch_mcp_method")(list(method="resources/list", id=1L), "2025-11-25"))
'
```

Or drive the live server with the official Inspector CLI:

```sh
Rscript conformance/everything-server.R &   # boots http://127.0.0.1:3001/mcp
npx @modelcontextprotocol/inspector --cli \
  --server-url http://127.0.0.1:3001/mcp --transport http \
  --header "MCP-Protocol-Version: 2025-11-25" --method resources/list
```

## Gotchas

- Commits in this repo are configured to sign via 1Password, which is
  unreachable in the agent sandbox → use `git commit --no-gpg-sign`.
- ellmer derives a tool's wire name from `fun`; pass `name =` to force it.
- Server→client methods (elicitation, sampling, progress) require real
  Streamable-HTTP **SSE** (GET currently returns 405). That transport work is
  sequential and gates those features — see the SEP guide's dependency graph.
