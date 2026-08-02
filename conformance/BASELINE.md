# MCP Conformance Baseline — forked `mcptools`

**System under test:** `conformance/everything-server.R` (forked `posit-dev/mcptools`, vendored at v1.0.1, built from source in this repo).
**Harness:** `@modelcontextprotocol/conformance@0.1.16`, **server mode**, Streamable HTTP at `http://127.0.0.1:3001/mcp`.
**Spec version:** `2025-11-25`.
**Result:** **4 passed / 27 failed** (31 scenarios; 2 SSE scenarios run 0 checks on this server).

Reproduce with `make conformance` (output saved to `conformance/last-run.txt`).

> This file records the **original upstream baseline**. For live status see below.

## Progress since baseline

**FULLY CONFORMANT ACROSS BOTH SUPPORTED SPEC VERSIONS (server mode). `make conformance` runs a two-leg matrix and exits 0:**
- **`2025-11-25`: 46 passed / 0 failed** on harness `@modelcontextprotocol/conformance@0.1.16`, `server: []`.
- **`2026-07-28` (GA stateless lifecycle): 113 passed / 0 failed** on harness `@modelcontextprotocol/conformance@0.2.0-alpha.10`, across all 40 dated scenarios — `server-stateless` (30/30), `caching`, standard/custom HTTP header validation, `dns-rebinding-protection`, SSE `tools/call`, NDJSON `subscriptions/listen`, and the full `input-required-result` MRTR group (elicitation / sampling / list-roots / request-state / multi-round / tamper-rejection / capability-filtering / validation). The one baseline entry, `sep-2164-resource-not-found`, is a documented `alpha.10` comparator quirk — its own assertions are 2/0 green.

Each spec leg is pinned to an appropriate harness release (the stable spec on the last stable harness `0.1.16`; the GA spec on `0.2.0-alpha.10`, the first release accepting the dated `2026-07-28` version) and both are overridable via `CONFORMANCE_2025_VERSION` / `CONFORMANCE_2026_VERSION`. Each runs `server --suite all --spec-version <version>` against its own ratchet (`expected-failures.yml` / `expected-failures-2026-07-28.yml`). The stateless leg adds per-request `_meta` + `MCP-Protocol-Version` validation, the full stateless error table (`-32020`/`-32021`/`-32022`/`-32602`, `404`/`-32601` for removed methods), `server/discover`, caching hints (`ttlMs`/`cacheScope` + `resultType:"complete"`), and HMAC-protected opaque request state (`R/mcp-stateless.R`, `R/mcp-mrtr.R`). Cross-version routing keeps the stateful 2025-11-25 / 2025-06-18 path intact.

---

**Prior milestone — `2025-11-25` FULLY CONFORMANT (server mode): 46 passed / 0 failed on harness `0.1.16`, `server: []`.**
Every server-mode scenario now passes — including the SSE-gated streaming set
(`tools-call-with-logging`, `tools-call-with-progress`, `tools-call-sampling`,
`tools-call-elicitation`, `elicitation-sep1034-defaults`, `elicitation-sep1330-enums`,
`server-sse-polling`, `server-sse-multiple-streams`), which required a raw-socket
Streamable-HTTP transport (buffered SSE for logging/progress; long-lived GET event
streams with `id:`/`retry:`/replay; bidirectional sampling/elicitation correlation;
`MCP-Session-Id` lifecycle with DELETE) because httpuv's Rook interface cannot stream.

Delivered across five workspaces merged into the foundation branch:
- **core tool content types** — `ping`, `tools-call-{simple-text,image,audio,embedded-resource,mixed-content,error}`, `json-schema-2020-12`
- **resources** — list / read-text / read-binary / templates-read / subscribe / unsubscribe
- **prompts** — list / get-simple / get-with-args / get-embedded-resource / get-with-image
- **completion + logging** — `completion-complete`, `logging-set-level`
- **SSE streaming transport** — the 8 SSE-gated scenarios above

Also fixed the two correctness bugs below (honest capabilities; unknown-tool → `isError`).

## Passing (4)
- `server-initialize`
- `tools-list`
- `dns-rebinding-protection` (2 checks)

`server-sse-polling` and `server-sse-multiple-streams` report `0 passed, 0 failed` in the summary, but the baseline evaluator treats a scenario with no successful checks as a failure, so they are also listed in `expected-failures.yml` (29 baseline entries total).

## Failing (27)

Failures split into two kinds:

### A. Fixture gap — `tools/call` works; the server just lacks the named everything-server tools
These fail only because the server does not yet expose the specific tools/behaviours the scenario calls (image/audio/embedded-resource/mixed content, deliberate error, progress, logging, sampling/elicitation-from-tool, raw JSON-Schema 2020-12).
- `tools-call-simple-text`
- `tools-call-image`
- `tools-call-audio`
- `tools-call-embedded-resource`
- `tools-call-mixed-content`
- `tools-call-with-logging`
- `tools-call-error`
- `tools-call-with-progress`
- `tools-call-sampling`
- `tools-call-elicitation`
- `json-schema-2020-12`

### B. Structural gap — method genuinely unimplemented (`-32601 Method not found`)
- `ping`
- `logging-set-level`
- `completion-complete`
- `resources-list`, `resources-read-text`, `resources-read-binary`, `resources-templates-read`, `resources-subscribe`, `resources-unsubscribe`
- `prompts-list`, `prompts-get-simple`, `prompts-get-with-args`, `prompts-get-embedded-resource`, `prompts-get-with-image`
- `elicitation-sep1034-defaults`, `elicitation-sep1330-enums`

## Known bugs surfaced by the baseline
1. **False capability advertisement** — `capabilities()` advertises `resources` and `prompts` but no such methods are implemented (spec violation).
2. **Unknown-tool error code** — calling an unknown tool returns JSON-RPC `-32601 Method not found`. Per spec an unknown tool should be a tool-level result with `isError: true` (or `-32602`), not method-not-found. Relevant to `tools-call-error`.
3. **No `2026-07-28` support** — the package tops out at `2025-11-25`; the GA stateless-lifecycle version is unimplemented.

## Wire-name gotcha (not a bug)
`ellmer::tool(fun = rnorm, ...)` registers the tool under the wire name **`rnorm`** (derived from `fun`), not the R list element name. `tools/call` works when the correct wire name is used.
