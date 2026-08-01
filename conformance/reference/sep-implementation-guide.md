# MCP Server SEP Implementation Guide

> Research date: 2026-08-01  
> Protocol versions covered: **2025-11-25** (current GA), **2026-07-28** (new GA — "stateless lifecycle")  
> Schema sources: `modelcontextprotocol/modelcontextprotocol` schema/2025-11-25/schema.ts and schema/2026-07-28/schema.ts  
> Conformance source: `modelcontextprotocol/conformance` src/scenarios/

---

## 1. Resources

### Governing SEPs
| SEP | Description |
|-----|-------------|
| No dedicated SEP — core spec since inception | `resources/list`, `resources/read`, `resources/templates/list` |
| SEP-2164 (draft/2026-07-28) | Resource-not-found error semantics: return -32602, not empty `contents[]` |
| SEP-2575 (2026-07-28) | `subscriptions/listen` replaces `resources/subscribe` / `resources/unsubscribe` |
| SEP-2549 (2025-11-25) | Caching: `ttlMs` + `cacheScope` on list results |

### JSON-RPC Shapes (2025-11-25)

```json
// resources/list request (paginated)
{ "jsonrpc":"2.0","id":1,"method":"resources/list","params":{"cursor":"opaque-token"} }

// resources/list result
{
  "resources": [
    { "uri":"test://static-text","name":"Example","description":"...","mimeType":"text/plain","size":42 }
  ],
  "nextCursor": "next-page-token"   // absent = last page
}

// resources/templates/list result
{ "resourceTemplates": [{ "uriTemplate":"test://template/{id}/data","name":"...","mimeType":"application/json" }], "nextCursor": null }

// resources/read request
{ "jsonrpc":"2.0","id":2,"method":"resources/read","params":{"uri":"test://static-text"} }

// resources/read result — TEXT
{ "contents": [{ "uri":"test://static-text","mimeType":"text/plain","text":"This is the content." }] }

// resources/read result — BINARY (base64 blob)
{ "contents": [{ "uri":"test://static-binary","mimeType":"image/png","blob":"iVBORw0KGgo..." }] }

// resources/subscribe (2025-11-25 only)
{ "jsonrpc":"2.0","id":3,"method":"resources/subscribe","params":{"uri":"test://watched"} }
// result: {}

// resources/unsubscribe (2025-11-25 only)
{ "jsonrpc":"2.0","id":4,"method":"resources/unsubscribe","params":{"uri":"test://watched"} }
// result: {}

// notifications/resources/updated (server → client)
{ "jsonrpc":"2.0","method":"notifications/resources/updated","params":{"uri":"test://watched"} }

// notifications/resources/list_changed (server → client)
{ "jsonrpc":"2.0","method":"notifications/resources/list_changed","params":{} }
```

### 2026-07-28 Changes
- `resources/subscribe` / `resources/unsubscribe` **removed** → use `subscriptions/listen` with `notifications.resourceSubscriptions: ["uri1","uri2"]`
- `notifications/resources/list_changed` only arrives on a `subscriptions/listen` stream when client sets `resourcesListChanged: true`
- `ReadResourceResult` extends `CacheableResult` → must include `ttlMs` (number, ≥0) and `cacheScope` ("public"|"private")
- `ListResourcesResult` extends `PaginatedResult, CacheableResult` — same `ttlMs`/`cacheScope` requirement
- `ReadResourceRequestParams` extends `InputResponseRequestParams` — can carry `inputResponses`/`requestState` for MRTR

### Capability Advertisement
```json
// Server capabilities for resources (in initialize result / server/discover)
"resources": {
  "subscribe": true,        // supports resources/subscribe (2025-11-25 only)
  "listChanged": true       // supports notifications/resources/list_changed
}
```
- Must declare `subscribe: true` before client can send `resources/subscribe`
- Must declare `listChanged: true` to emit `notifications/resources/list_changed`

### Conformance Test Scenarios
| Scenario | Spec Version | Description |
|----------|-------------|-------------|
| `resources-list` | 2025-06-18+ | Lists resources; validates uri+name present on each |
| `resources-read-text` | 2025-06-18+ | Reads `test://static-text`, validates text field |
| `resources-read-binary` | 2025-06-18+ | Reads `test://static-binary`, validates blob field |
| `resources-templates-read` | 2025-06-18+ | Reads `test://template/123/data`, validates `{id}` substitution |
| `resources-subscribe` | 2025-06-18+, **removed in 2026-07-28** | Subscribe returns `{}` |
| `resources-unsubscribe` | 2025-06-18+, **removed in 2026-07-28** | Unsubscribe returns `{}` |
| `sep-2164-resource-not-found` | 2026-07-28+ (draft) | Missing URI → -32602 with `data.uri` |

Source: `modelcontextprotocol/conformance:src/scenarios/server/resources.ts`

### Gotchas / Advice
- **Binary blob must be base64-encoded** — the `blob` field is `@format byte`. Use standard base64, not URL-safe.
- **`uri` field in `contents` must match the requested URI** (or the sub-resource URI if server splits content).
- **Pagination cursor is opaque** — clients treat it as a black box. Servers must not reveal encoding. An absent `nextCursor` means the end of the list.
- **Error for not-found (SEP-2164)**: Return `-32602 InvalidParams` with `data: { uri: "<requested-uri>" }`. Do NOT return a result with empty `contents: []` — that is ambiguous.
- **`resources/subscribe` advertised separately from `listChanged`** — a server CAN support `subscribe` without supporting list change notifications, and vice versa.
- **2026-07-28 migration**: `resources/subscribe` is gone. Use `subscriptions/listen` with `SubscriptionFilter.resourceSubscriptions`. Clients receive `notifications/subscriptions/acknowledged` first, then updates.
- **Resource URI can use any scheme** — `test://`, `file://`, `https://`, custom schemes all allowed.

---

## 2. Prompts

### Governing SEPs
No dedicated SEP — core spec since inception. Conformance scenarios cover all variants.

### JSON-RPC Shapes (2025-11-25 and 2026-07-28 — unchanged)

```json
// prompts/list request (paginated)
{ "jsonrpc":"2.0","id":1,"method":"prompts/list","params":{} }

// prompts/list result
{
  "prompts": [
    { "name":"code-review","title":"Code Review","description":"Review code","arguments":[{"name":"code","description":"The code","required":true}] }
  ],
  "nextCursor": null
}

// prompts/get request
{ "jsonrpc":"2.0","id":2,"method":"prompts/get","params":{"name":"code-review","arguments":{"code":"fn main() {}"}} }

// prompts/get result — simple text
{
  "description": "A code review prompt",
  "messages": [
    { "role":"user","content":{"type":"text","text":"Review this code: fn main() {}"} }
  ]
}

// prompts/get result — with image
{
  "messages": [
    { "role":"user","content":{"type":"image","data":"<base64>","mimeType":"image/png"} }
  ]
}

// prompts/get result — with embedded resource
{
  "messages": [
    { "role":"user","content":{"type":"resource","resource":{"uri":"file:///readme.md","mimeType":"text/plain","text":"# README"}} }
  ]
}

// notifications/prompts/list_changed
{ "jsonrpc":"2.0","method":"notifications/prompts/list_changed","params":{} }
```

### Capability Advertisement
```json
"prompts": { "listChanged": true }
```

### 2026-07-28 Changes
- `GetPromptRequestParams` extends `InputResponseRequestParams` — supports MRTR
- `GetPromptResultResponse` can return `GetPromptResult | InputRequiredResult`
- `ListPromptsResult` extends `CacheableResult` — add `ttlMs` + `cacheScope`
- `notifications/prompts/list_changed` only on `subscriptions/listen` with `promptsListChanged: true`

### Conformance Test Scenarios
| Scenario | Description |
|----------|-------------|
| `prompts-list` | Lists prompts; validates name present |
| `prompts-get-simple` | Gets prompt without args |
| `prompts-get-with-args` | Gets prompt with arguments substituted |
| `prompts-get-embedded-resource` | Gets prompt with embedded resource content |
| `prompts-get-with-image` | Gets prompt with image content block |

Source: `modelcontextprotocol/conformance:src/scenarios/server/prompts.ts`

### Gotchas / Advice
- **`PromptArgument.name` is the identifier** — used as the key in `arguments: { [name]: value }`.
- **Required vs optional arguments**: `required?: boolean` defaults to false. Servers should validate required args and return -32602 if missing.
- **`ContentBlock` in `PromptMessage`** is `TextContent | ImageContent | AudioContent | ResourceLink | EmbeddedResource` — the full union. A prompt message can embed any content type.
- **`EmbeddedResource.type` is `"resource"`** (not `"resource_link"`). `ResourceLink.type` is `"resource_link"`.
- **Image content**: `data` field is base64-encoded, `mimeType` required.
- **`notifications/prompts/list_changed` can fire without prior subscription** in 2025-11-25 — server may issue proactively; client should handle gracefully.
- **Pagination**: Same cursor semantics as resources.

---

## 3. Completion

### Governing SEPs
| SEP | Description |
|-----|-------------|
| SEP-1613 | JSON Schema 2020-12 support for tool schemas |
| SEP-2106 | JSON Schema network `$ref` dereferencing |

No dedicated SEP for completion itself — core spec.

### JSON-RPC Shapes (unchanged 2025-11-25 → 2026-07-28)

```json
// completion/complete request — prompt argument
{
  "jsonrpc":"2.0","id":1,"method":"completion/complete",
  "params":{
    "ref":{"type":"ref/prompt","name":"code-review"},
    "argument":{"name":"language","value":"py"},
    "context":{"arguments":{"style":"verbose"}}
  }
}

// completion/complete request — resource template argument
{
  "jsonrpc":"2.0","id":1,"method":"completion/complete",
  "params":{
    "ref":{"type":"ref/resource","uri":"test://template/{language}/data"},
    "argument":{"name":"language","value":"py"}
  }
}

// completion/complete result
{
  "completion":{
    "values":["python","pypy"],
    "total":2,
    "hasMore":false
  }
}
```

### Capability Advertisement
```json
"completions": {}
```
Must be declared; client should not call `completion/complete` if absent.

### Gotchas / Advice
- **`ref` type determines scope**: `ref/prompt` → completions for prompt arguments; `ref/resource` → completions for URI template variables.
- **`context.arguments`** carries already-resolved variables for multi-argument templates — use this for dependent completions.
- **`values` max 100 items** — schema enforces `@maxItems 100`. Return `hasMore: true` if more exist.
- **`total` is optional** — use only if you know the exact count.
- **Server must declare `completions: {}` capability** — otherwise Method Not Found (-32601) is appropriate response.
- **`PromptReference.name`** is the prompt name (same as in prompts/list); `ResourceTemplateReference.uri` is the URI template string.

---

## 4. Logging

### Governing SEPs
| SEP | Description |
|-----|-------------|
| SEP-2577 (2026-07-28) | Logging deprecated: replaces `logging/setLevel` RPC with per-request `_meta["io.modelcontextprotocol/logLevel"]` |

### JSON-RPC Shapes (2025-11-25)

```json
// Client request to set log level
{ "jsonrpc":"2.0","id":1,"method":"logging/setLevel","params":{"level":"debug"} }
// Result: {}

// Server notification (log message)
{
  "jsonrpc":"2.0","method":"notifications/message",
  "params":{ "level":"error","logger":"mymodule","data":"Connection failed: timeout" }
}
```

**LoggingLevel values** (syslog RFC-5424 order, least to most severe):
`"debug" | "info" | "notice" | "warning" | "error" | "critical" | "alert" | "emergency"`

Server sends all logs at the set level AND MORE SEVERE.

### Capability Advertisement
```json
"logging": {}    // 2025-11-25: server declares it supports logging
```

### 2026-07-28 Changes (SEP-2577 — DEPRECATED)
- `logging/setLevel` RPC **removed** — server MUST NOT accept it
- `logging` capability **deprecated**
- Client opts in per-request: `_meta["io.modelcontextprotocol/logLevel"]` = level string
- If absent from `_meta`, server MUST NOT send any `notifications/message` for that request
- `notifications/message` + `LoggingMessageNotification` remain in schema for 12+ months (backwards compat)

### Gotchas / Advice
- **2025-11-25**: Server MAY send logs even without `logging/setLevel` if it has its own defaults. The spec says "If no logging/setLevel request has been sent... the server MAY decide which messages to send automatically."
- **2026-07-28**: Per-request opt-in means each POST independently sets log level via `_meta`. Servers must not carry level across requests.
- **`data` field is `unknown`** — can be any JSON-serializable value (string, object, etc.). Not just a string.
- **`logger` field is optional** — identifies the source module.
- **Conformance test** (`logging-set-level`) validates that after `setLevel("debug")`, the server emits log notifications during a tool call (`tools-call-with-logging` scenario uses `test_logging` tool).
- **Build for 2025-11-25 first** — implement `logging/setLevel` + `notifications/message`. For 2026-07-28, suppress all if `_meta` has no `logLevel`.

---

## 5. Elicitation

### Governing SEPs
| SEP | Description |
|-----|-------------|
| SEP-1034 | Default values in elicitation schemas (string, number, integer, boolean, enum) |
| SEP-1330 | Enum schema improvements: untitled/titled single-select, untitled/titled multi-select, legacy `enumNames` |
| SEP-2322 | Multi-round-trip (MRTR) `InputRequiredResult` — replaces direct server-to-client in 2026-07-28 |

### JSON-RPC Shapes (2025-11-25 — direct server-to-client request)

```json
// Server sends elicitation/create to client (during tools/call SSE stream)
{
  "jsonrpc":"2.0","id":99,"method":"elicitation/create",
  "params":{
    "mode":"form",
    "message":"Please provide your details",
    "requestedSchema":{
      "type":"object",
      "properties":{
        "name":{"type":"string","title":"Name","default":"John Doe"},
        "age":{"type":"integer","title":"Age","default":30},
        "score":{"type":"number","default":95.5},
        "verified":{"type":"boolean","default":true},
        "status":{"type":"string","enum":["active","inactive","pending"],"default":"active"}
      },
      "required":["name"]
    }
  }
}

// Client response
{
  "jsonrpc":"2.0","id":99,
  "result":{
    "action":"accept",
    "content":{"name":"Jane Smith","age":25,"score":88.0,"verified":false,"status":"inactive"}
  }
}

// OR: user declined
{ "jsonrpc":"2.0","id":99,"result":{"action":"decline"} }

// OR: user cancelled
{ "jsonrpc":"2.0","id":99,"result":{"action":"cancel"} }
```

### SEP-1330 Enum Schema Variants

```json
// 1. Untitled single-select (simple enum array)
{ "type":"string","enum":["option1","option2","option3"] }

// 2. Titled single-select (oneOf with const/title pairs)
{ "type":"string","oneOf":[{"const":"value1","title":"First Option"},{"const":"value2","title":"Second Option"}] }

// 3. Legacy titled (DEPRECATED — use oneOf instead)
{ "type":"string","enum":["opt1","opt2","opt3"],"enumNames":["Option One","Option Two","Option Three"] }

// 4. Untitled multi-select (array with items.enum)
{ "type":"array","items":{"type":"string","enum":["option1","option2","option3"]},"minItems":1,"maxItems":3 }

// 5. Titled multi-select (array with items.anyOf const/title)
{ "type":"array","items":{"anyOf":[{"const":"value1","title":"First Choice"},{"const":"value2","title":"Second Choice"}]} }
```

### SEP-1034 Default Values
All primitive schema types support `default`:
- `StringSchema.default?: string`
- `NumberSchema.default?: number` (works for both `"number"` and `"integer"` type)
- `BooleanSchema.default?: boolean`
- `UntitledSingleSelectEnumSchema.default?: string` (must be in `enum` array)
- `TitledSingleSelectEnumSchema.default?: string`

### URL Elicitation Mode (2025-11-25)
```json
{
  "mode":"url",
  "message":"Complete OAuth flow",
  "url":"https://auth.example.com/oauth?redirect=..."
}
// Result: { "action": "accept" }  (no content for URL mode)

// Error if client doesn't support URL mode (-32042 in 2025-11-25):
{ "error":{"code":-32042,"data":{"elicitations":[...]}} }
```

### 2026-07-28 Changes (MRTR / InputRequiredResult — SEP-2322)
In 2026-07-28, servers return `InputRequiredResult` INSTEAD of making a separate JSON-RPC request:

```json
// tools/call result → server needs elicitation (instead of calling client):
{
  "resultType":"input_required",
  "inputRequests":{
    "userForm": {
      "method":"elicitation/create",
      "params":{"mode":"form","message":"Enter details","requestedSchema":{...}}
    }
  },
  "requestState":"<opaque-blob-for-server>"
}

// Client retries the original tools/call with responses:
{
  "method":"tools/call",
  "params":{
    "name":"the_tool","arguments":{},
    "inputResponses":{"userForm":{"action":"accept","content":{...}}},
    "requestState":"<opaque-blob-from-server>"
  }
}

// Final result:
{ "resultType":"complete","content":[{"type":"text","text":"Done"}] }
```

### Capability Advertisement
```json
// Client must declare elicitation capability
"elicitation": {
  "form": {},    // supports form mode
  "url": {}      // supports URL mode (optional)
}
```
- Server must check client capabilities BEFORE sending elicitation
- In 2025-11-25: If no `elicitation` capability, return -32602 or -32021
- In 2026-07-28: Use `MissingRequiredClientCapabilityError` (-32021) with `data.requiredCapabilities`

### Conformance Test Scenarios
| Scenario | SEP | Checks |
|----------|-----|--------|
| `tools-call-elicitation` | — | Basic elicitation during tool call |
| `elicitation-sep1034-defaults` | SEP-1034 | 5 checks: string/integer/number/enum/boolean defaults all present and correct |
| `elicitation-sep1330-enums` | SEP-1330 | 5 checks: all 5 enum variants present and correctly structured |
| `elicitation-sep1034-client-defaults` | SEP-1034 | Client side: honor defaults |

**Required tool names for conformance:**
- `test_elicitation_sep1034_defaults` — must trigger elicitation with the exact 5-field schema
- `test_elicitation_sep1330_enums` — must trigger elicitation with all 5 enum variants

Source: `modelcontextprotocol/conformance:src/scenarios/server/elicitation-defaults.ts`, `elicitation-enums.ts`

### Gotchas / Advice
- **Elicitation is FLAT** — `requestedSchema.properties` allows only `PrimitiveSchemaDefinition` (string/number/integer/boolean/enum). No nested objects or arrays (except enum arrays).
- **Default validation for enum**: The `default` value MUST be a member of the `enum` array.
- **`enumNames` is deprecated** — new code should use `oneOf` with `const/title` instead.
- **Titled multi-select uses `items.anyOf`** — NOT `items.oneOf`. This is a spec-specific pattern.
- **Client must validate `inputResponses` at runtime** — do not trust generic TypeScript generics for schema validation. The MRTR example bug (typescript-sdk#2542) shows how unchecked responses can lead to security issues.
- **`action: "cancel"` vs `"decline"`**: "cancel" = user dismissed without choice; "decline" = explicit refusal. Server should handle all three.
- **Scenarios `elicitation-sep1034-defaults` and `elicitation-sep1330-enums` are marked `removedIn: DRAFT_PROTOCOL_VERSION`** — these only apply to 2025-11-25. For 2026-07-28, elicitation uses MRTR.
- **`requestState` is opaque** — clients must not interpret it, just echo it back verbatim on retry.

---

## 6. Sampling

### Governing SEPs
| SEP | Description |
|-----|-------------|
| SEP-2596 | Deprecate `includeContext` values `"thisServer"` / `"allServers"` |
| SEP-2577 (2026-07-28) | Entire `sampling/createMessage` deprecated — use MRTR `InputRequiredResult` |

### JSON-RPC Shapes (2025-11-25 — direct server-to-client request)

```json
// Server sends sampling/createMessage to client (during SSE stream)
{
  "jsonrpc":"2.0","id":100,"method":"sampling/createMessage",
  "params":{
    "messages":[{"role":"user","content":{"type":"text","text":"What is 2+2?"}}],
    "maxTokens":100,
    "modelPreferences":{
      "hints":[{"name":"claude-3-5-sonnet"}],
      "intelligencePriority":0.8,
      "speedPriority":0.2
    },
    "systemPrompt":"You are a helpful assistant.",
    "includeContext":"none"
  }
}

// Client response
{
  "jsonrpc":"2.0","id":100,
  "result":{
    "role":"assistant",
    "content":{"type":"text","text":"4"},
    "model":"claude-3-5-sonnet-20241022",
    "stopReason":"endTurn"
  }
}
```

### Sampling with Tools (2025-11-25+)
```json
// Request with tools
{
  "messages":[...],
  "maxTokens":1000,
  "tools":[{"name":"get_weather","description":"...","inputSchema":{"type":"object","properties":{"city":{"type":"string"}}}}],
  "toolChoice":{"mode":"auto"}
}

// Client returns tool use
{ "role":"assistant","content":{"type":"tool_use","id":"tu_1","name":"get_weather","input":{"city":"London"}} }

// Client then returns final answer after providing tool result in follow-up
{ "role":"assistant","content":{"type":"text","text":"It's 15°C in London"},"stopReason":"endTurn" }
```

### ModelPreferences
```typescript
interface ModelPreferences {
  hints?: ModelHint[];          // model name substrings, in priority order
  costPriority?: number;        // 0=unimportant, 1=most important
  speedPriority?: number;       // 0=unimportant, 1=most important
  intelligencePriority?: number;// 0=unimportant, 1=most important
}
```

### Capability Advertisement (2025-11-25)
```json
// Client declares:
"sampling": {
  "context": {},   // supports includeContext: "thisServer"/"allServers"
  "tools": {}      // supports tools + toolChoice params
}
```
- Server must check client has `sampling` capability before sending `sampling/createMessage`
- If `tools` or `toolChoice` provided but client has no `sampling.tools`, client MUST return error
- `includeContext` is soft-deprecated — only use `"none"` unless client declares `sampling.context`

### SamplingMessage Content Types
```typescript
type SamplingMessageContentBlock =
  | TextContent       // { type: "text", text: string }
  | ImageContent      // { type: "image", data: string (base64), mimeType: string }
  | AudioContent      // { type: "audio", data: string (base64), mimeType: string }
  | ToolUseContent    // { type: "tool_use", id: string, name: string, input: {...} }
  | ToolResultContent // { type: "tool_result", toolUseId: string, content: ContentBlock[], isError?: boolean }
```

### 2026-07-28 Changes (SEP-2577 — DEPRECATED)
- `sampling/createMessage` **deprecated** but remains in schema for 12+ months
- In 2026-07-28, server uses MRTR: returns `InputRequiredResult` with `inputRequests.key = CreateMessageRequest`
- Client provides `inputResponses.key = CreateMessageResult` on retry
- `SamplingMessage`, `CreateMessageRequest`, `CreateMessageResult`, `ModelPreferences`, `ToolUseContent`, `ToolResultContent`, `ToolChoice` all marked `@deprecated`

### Gotchas / Advice
- **`maxTokens` is required** — not optional. A server forgetting this causes client errors.
- **Client has full discretion over model selection** — `modelPreferences` are advisory only.
- **Human-in-the-loop**: Client SHOULD inform user before sampling AND before returning result. This is a security/trust requirement.
- **`ToolResultContent.toolUseId` must match a previous `ToolUseContent.id`** — multi-turn tool use requires tracking IDs.
- **`SamplingMessage.content` can be a single block OR an array** (`SamplingMessageContentBlock | SamplingMessageContentBlock[]`) — handle both in deserialization.
- **Tool results must not be mixed with other content in the same message** — spec says mixing is invalid (client returns -32602).
- **Conformance** (`tools-call-sampling`) tests that server can initiate sampling during a tool call.
- **`stopReason: "toolUse"`** — new value added alongside classic ones; open string for provider-specific values.

---

## 7. Progress + Cancellation

### Governing SEPs
No dedicated SEP — core spec since inception. SEP-2575 modified cancellation direction.

### JSON-RPC Shapes

```json
// Client request with progressToken
{
  "jsonrpc":"2.0","id":5,"method":"tools/call",
  "params":{"name":"slow_tool","arguments":{},"_meta":{"progressToken":"tok-abc"}}
}

// Server sends progress notifications on SSE stream (or stdio)
{ "jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"tok-abc","progress":25,"total":100,"message":"Processing..."}  }
{ "jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"tok-abc","progress":100,"total":100,"message":"Done"} }

// Cancellation (2025-11-25 — either side)
{ "jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":5,"reason":"User clicked cancel"} }

// Cancellation (2026-07-28 — client only, plus server for subscriptions/listen close)
{ "jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":5,"reason":"User clicked cancel"} }
```

### ProgressToken Types
```typescript
type ProgressToken = string | number;
```
Server must echo the token exactly. Numeric tokens must remain numeric (don't stringify).

### Transport-Layer Progress (Streamable HTTP)
- Client sends POST with JSON body; server responds with SSE stream (text/event-stream)
- Progress notifications arrive as SSE `data:` events on that stream before the final result
- Multiple requests can share the same HTTP connection but each POST opens its own SSE stream
- The final response is the last event on the SSE stream

### 2026-07-28 Changes
- **`requestId` in `CancelledNotificationParams` is now required** (was optional in 2025-11-25)
- **Server MUST NOT use `notifications/cancelled` for anything other than closing a `subscriptions/listen` stream** — client-to-server cancel is the only direction for general requests
- **`notifications/cancelled` in 2025-11-25**: `requestId?: RequestId` + optional `reason`; either side can send

### Gotchas / Advice
- **Progress must be monotonically increasing** — `progress` should only increase. `total` can be omitted when unknown.
- **Server is NOT obligated to send progress** even if client provides `progressToken` — it's a request, not a requirement.
- **Cancellation may arrive after request completes** — server must handle gracefully (ignore if already done).
- **Client MUST NOT cancel the `initialize` request** (2025-11-25 only — stateful lifecycle).
- **On Streamable HTTP**: Progress and server-initiated requests (sampling/elicitation) are multiplexed on the SSE stream opened by the POST. Server can send arbitrary JSON-RPC messages on that stream before the final result.
- **Conformance** (`tools-call-with-progress`): Tool named `test_progress` must accept no args, emit ≥1 progress notification during execution.
- **`message` in progress notification** is optional but useful for UX.

---

## 8. Roots

### Governing SEPs
| SEP | Description |
|-----|-------------|
| SEP-2577 (2026-07-28) | Entire roots feature deprecated |

### JSON-RPC Shapes (2025-11-25 — server requests from client)

```json
// Server sends roots/list to client
{ "jsonrpc":"2.0","id":200,"method":"roots/list","params":{} }

// Client response
{
  "jsonrpc":"2.0","id":200,
  "result":{ "roots":[{"uri":"file:///workspace/my-project","name":"My Project"}] }
}

// Server notification when roots change
{ "jsonrpc":"2.0","method":"notifications/roots/list_changed","params":{} }
```

### Capability Advertisement (2025-11-25)
```json
// Client declares in initialize:
"roots": {
  "listChanged": true    // supports notifications/roots/list_changed
}
```
- Server can only request `roots/list` if client declared `roots` capability
- Server can only expect `notifications/roots/list_changed` if `listChanged: true`

### 2026-07-28 Status
- `roots/list`, `ListRootsRequest`, `ListRootsResult`, `Root`, `notifications/roots/list_changed` all marked **`@deprecated`** in 2026-07-28 schema (SEP-2577)
- `roots` capability in `ClientCapabilities` deprecated
- Remains in schema for 12+ months backward compatibility

### Root URIs
```typescript
interface Root {
  uri: string;    // MUST start with "file://" currently
  name?: string;  // optional human-readable label
}
```
- URIs currently restricted to `file://` scheme
- This restriction may be relaxed in future versions

### Gotchas / Advice
- **Roots is server-to-client** — uncommon direction. Server must open SSE stream or use stdio to send this request.
- **On Streamable HTTP**: Server can't spontaneously make requests; it can only send JSON-RPC requests on the SSE stream opened by a client POST. This limits roots usage — typically done during initialize handshake or as part of a tool call.
- **`listChanged` must be declared by client** — if false/absent, server must not rely on getting change notifications.
- **2026-07-28**: Implement for 2025-11-25 compatibility but mark it as deprecated and plan migration.
- **No conformance test** in the conformance suite specifically for `roots/list` as a standalone scenario — it's tested implicitly via `tools-call-sampling`.

---

## 9. Streamable HTTP Transport + Stateless Lifecycle (2026-07-28)

### Governing SEPs
| SEP | Description |
|-----|-------------|
| SEP-2575 (Final, 2026-07-28) | Make MCP stateless: per-request `_meta`, `server/discover`, `subscriptions/listen` |
| SEP-2243 | HTTP header standardization: `Mcp-Method`, `Mcp-Name`, `MCP-Protocol-Version`, case-insensitivity |
| SEP-1699 | SSE polling: GET endpoint for multiple server-to-client streams (2025-11-25 only) |
| GHSA-w48q-cv73-mx4w | DNS rebinding protection for localhost servers |

### 2025-11-25 Transport Overview (Stateful)

**Initialize Handshake Required:**
```json
// Step 1: Client POSTs initialize
POST /mcp HTTP/1.1
Content-Type: application/json
MCP-Protocol-Version: 2025-11-25
Origin: http://localhost:3000

{ "jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{...},"clientInfo":{...}} }

// Server responds with MCP-Session-Id
HTTP/1.1 200 OK
Mcp-Session-Id: sess-abc123
Content-Type: application/json
{ "jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25","capabilities":{...},"serverInfo":{...}} }

// Step 2: Client sends initialized notification
POST /mcp HTTP/1.1
Mcp-Session-Id: sess-abc123
{ "jsonrpc":"2.0","method":"notifications/initialized" }

// Step 3: Normal requests
POST /mcp HTTP/1.1
Mcp-Session-Id: sess-abc123
{ "jsonrpc":"2.0","id":2,"method":"tools/list" }
```

**SSE Streaming for Long Responses:**
```
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache

data: {"jsonrpc":"2.0","method":"notifications/progress","params":{"progressToken":"tok","progress":50}}

data: {"jsonrpc":"2.0","id":2,"result":{"tools":[...]}}
```

**GET Endpoint (SSE polling — SEP-1699, 2025-11-25):**
```
GET /mcp HTTP/1.1
Mcp-Session-Id: sess-abc123
Accept: text/event-stream

// Server holds SSE connection open for server-initiated requests:
data: {"jsonrpc":"2.0","id":99,"method":"sampling/createMessage","params":{...}}

// Client responds to server-initiated request via POST:
POST /mcp HTTP/1.1
Mcp-Session-Id: sess-abc123
{ "jsonrpc":"2.0","id":99,"result":{...} }
```

**Multiple SSE Streams (SEP-1699):**
- Client can open multiple concurrent GET streams
- Each stream gets notifications independently
- Server acknowledges and tracks active streams
- Conformance: `sse-multiple-streams` (2 checks)

### 2026-07-28 Transport Overview (Stateless)

**No initialize handshake — per-request `_meta`:**
```json
// Every request carries full identity and capabilities in _meta
POST /mcp HTTP/1.1
Content-Type: application/json
MCP-Protocol-Version: 2026-07-28
Accept: application/json, text/event-stream

{
  "jsonrpc":"2.0","id":1,"method":"tools/list",
  "params":{
    "_meta":{
      "io.modelcontextprotocol/protocolVersion":"2026-07-28",
      "io.modelcontextprotocol/clientInfo":{"name":"my-client","version":"1.0.0"},
      "io.modelcontextprotocol/clientCapabilities":{"elicitation":{"form":{}}}
    }
  }
}
```

**`server/discover` (replaces initialize for capability discovery):**
```json
// Client may call server/discover to learn capabilities before sending requests
{ "jsonrpc":"2.0","id":1,"method":"server/discover","params":{"_meta":{...}} }
// Server response (CacheableResult):
{
  "resultType":"complete",
  "supportedVersions":["2026-07-28","2025-11-25"],
  "capabilities":{"tools":{},"resources":{},"prompts":{}},
  "instructions":"This server...",
  "ttlMs":3600000,
  "cacheScope":"public",
  "_meta":{"io.modelcontextprotocol/serverInfo":{"name":"my-server","version":"1.0"}}
}
```

**`subscriptions/listen` (replaces GET SSE endpoint):**
```json
// Client opens long-lived stream for notifications
POST /mcp HTTP/1.1
Content-Type: application/json
MCP-Protocol-Version: 2026-07-28

{
  "jsonrpc":"2.0","id":2,"method":"subscriptions/listen",
  "params":{
    "_meta":{...},
    "notifications":{
      "toolsListChanged":true,
      "resourcesListChanged":true,
      "resourceSubscriptions":["file:///watched.txt"]
    }
  }
}

// Server holds SSE open; first message MUST be acknowledged notification:
data: {"jsonrpc":"2.0","method":"notifications/subscriptions/acknowledged","params":{"notifications":{"toolsListChanged":true,"resourcesListChanged":true,"resourceSubscriptions":["file:///watched.txt"]},"_meta":{"io.modelcontextprotocol/subscriptionId":2}}}

// Subsequent notifications carry subscriptionId:
data: {"jsonrpc":"2.0","method":"notifications/resources/updated","params":{"uri":"file:///watched.txt","_meta":{"io.modelcontextprotocol/subscriptionId":2}}}

// Server closes stream gracefully with SubscriptionsListenResult:
data: {"jsonrpc":"2.0","id":2,"result":{"resultType":"complete","_meta":{"io.modelcontextprotocol/subscriptionId":2}}}
```

### Error Codes (2026-07-28 — new)
```typescript
const HEADER_MISMATCH = -32020;                    // HTTP 400
const MISSING_REQUIRED_CLIENT_CAPABILITY = -32021;  // HTTP 400
const UNSUPPORTED_PROTOCOL_VERSION = -32022;        // HTTP 400
```

**`UnsupportedProtocolVersionError` example:**
```json
{
  "error":{"code":-32022,"message":"Unsupported protocol version",
    "data":{"supported":["2026-07-28","2025-11-25"],"requested":"2099-01-01"}}
}
```

**`MissingRequiredClientCapabilityError` example:**
```json
{
  "error":{"code":-32021,"message":"Client capability required",
    "data":{"requiredCapabilities":{"sampling":{}}}}
}
```

**`HeaderMismatchError` example (-32020):**
Returned when `MCP-Protocol-Version` header doesn't match `_meta["io.modelcontextprotocol/protocolVersion"]`.

### `resultType` Field (2026-07-28 Required)
ALL results in 2026-07-28 MUST include `resultType`:
```json
{ "resultType":"complete", ... }    // success
{ "resultType":"input_required", ... }  // MRTR
```
For backward compat: absent `resultType` from 2025-11-25 servers MUST be treated as `"complete"`.

### SEP-2243 HTTP Headers
| Header | Direction | Required | Notes |
|--------|-----------|----------|-------|
| `MCP-Protocol-Version` | Client→Server | Yes | Must match `_meta.io.mcp/protocolVersion` |
| `Accept` | Client→Server | Recommended | `application/json, text/event-stream` |
| `Content-Type` | Client→Server | Yes | `application/json` |
| `Mcp-Method` | Client→Server | Yes (2026-07-28) | JSON-RPC method name |
| `Mcp-Name` | Client→Server | Conditional | Tool name for `tools/call` |
| `Mcp-Session-Id` | Both | Conditional | 2025-11-25 session identifier |

Headers must be treated **case-insensitively**. Values must have leading/trailing whitespace trimmed. Mismatch between header and body → -32020.

### DNS Rebinding Protection
- **MUST** validate `Host` or `Origin` header on ALL incoming requests (localhost servers)
- Reject non-localhost `Host`/`Origin` with HTTP 4xx
- Accept: `localhost`, `127.0.0.1`, `[::1]` (with optional port)
- Reject: anything else (e.g., `evil.example.com`)
- Security advisory: `GHSA-w48q-cv73-mx4w` in typescript-sdk
- Conformance: `dns-rebinding-protection` (2 checks: rejected attack + accepted valid)

### Conformance Test Scenarios
| Scenario | SEP | Checks |
|----------|-----|--------|
| `server-initialize` | — | Initialize handshake (2025-11-25) |
| `server-stateless` | SEP-2575 | 22 checks covering all stateless requirements |
| `session-lifecycle` | — | MCP-Session-Id handling |
| `sse-multiple-streams` | SEP-1699 | Multiple concurrent GET SSE streams |
| `dns-rebinding-protection` | GHSA | Reject evil.example.com, accept localhost |
| `caching` | SEP-2549 | ttlMs/cacheScope on list results |

### Gotchas / Advice
- **Stateful (2025-11-25) and stateless (2026-07-28) are fundamentally different** — maintain both modes or decide on one. The conformance suite `--spec-version 2025-11-25` tests the stateful path; `--spec-version 2026-07-28` tests stateless.
- **Server MUST NOT send notifications before `subscriptions/listen` — `notifications/subscriptions/acknowledged` MUST be the FIRST message** on any listen stream.
- **`subscriptions/listen` subscription IDs** — the JSON-RPC `id` of the `subscriptions/listen` request IS the subscription ID. Echo it in `_meta["io.modelcontextprotocol/subscriptionId"]` on every notification.
- **`server/discover` is required** in 2026-07-28 (`Servers MUST implement server/discover`).
- **`io.modelcontextprotocol/clientInfo` is SHOULD-level** — servers must NOT reject requests that omit it.
- **`io.modelcontextprotocol/clientCapabilities` is required** — empty object `{}` means no optional capabilities.
- **MRTR on HTTP**: Server-to-client requests (elicitation, sampling) happen via `InputRequiredResult` on the same HTTP response — no separate SSE stream needed for them in 2026-07-28.
- **Duplicate in-flight request IDs** (typescript-sdk PR#2434): Server must reject a POST containing a request ID that's already in-flight with HTTP 400 + -32600. Cancelled requests must retire their ID.
- **`subscriptions/listen` closure**: Server sends `SubscriptionsListenResult` gracefully on shutdown; abrupt close has no response.
- **`notifications/cancelled` on stdio**: Server can send it to close a `subscriptions/listen` stream, referencing the stream's request ID.

---

## 10. structuredContent + Tool Output Schemas + Content Types

### Governing SEPs
| SEP | Description |
|-----|-------------|
| SEP-1613 | JSON Schema 2020-12 for tool schemas |
| SEP-2106 | JSON Schema network `$ref` dereferencing |

### JSON-RPC Shapes

```json
// Tool definition with outputSchema (in tools/list result)
{
  "name":"analyze_data",
  "description":"Analyzes data and returns structured results",
  "inputSchema":{
    "type":"object",
    "properties":{"data":{"type":"string"}},
    "required":["data"]
  },
  "outputSchema":{
    "$schema":"https://json-schema.org/draft/2020-12/schema",
    "type":"object",
    "properties":{
      "sentiment":{"type":"string","enum":["positive","negative","neutral"]},
      "confidence":{"type":"number"}
    },
    "required":["sentiment","confidence"]
  },
  "annotations":{
    "title":"Data Analyzer",
    "readOnlyHint":true,
    "destructiveHint":false,
    "idempotentHint":true,
    "openWorldHint":false
  }
}

// tools/call result with structured + unstructured content
{
  "content":[
    {"type":"text","text":"Analysis complete: positive sentiment (0.92)"}
  ],
  "structuredContent":{
    "sentiment":"positive",
    "confidence":0.92
  }
}

// tools/call result with error (isError: true — NOT a JSON-RPC error)
{
  "content":[{"type":"text","text":"Error: file not found"}],
  "isError":true
}

// tools/call result with image content
{
  "content":[
    {"type":"image","data":"<base64>","mimeType":"image/png"},
    {"type":"text","text":"Chart generated"}
  ]
}

// tools/call result with audio content
{ "content":[{"type":"audio","data":"<base64>","mimeType":"audio/wav"}] }

// tools/call result with embedded resource
{
  "content":[{
    "type":"resource",
    "resource":{"uri":"file:///result.csv","mimeType":"text/csv","text":"a,b,c\n1,2,3"}
  }]
}

// tools/call result with resource link (reference, not embedded)
{
  "content":[{
    "type":"resource_link",
    "uri":"file:///report.pdf","name":"Report","mimeType":"application/pdf"
  }]
}
```

### ContentBlock Union
```typescript
type ContentBlock =
  | TextContent        // type: "text", text: string
  | ImageContent       // type: "image", data: string (base64), mimeType: string
  | AudioContent       // type: "audio", data: string (base64), mimeType: string
  | ResourceLink       // type: "resource_link", uri, name, ...Resource fields
  | EmbeddedResource   // type: "resource", resource: TextResourceContents | BlobResourceContents
```

### Error Semantics — Critical Rules
1. **Tool errors from the tool itself** → `isError: true` in `CallToolResult.content`, NOT a JSON-RPC error
2. **Unknown tool name** → `-32602 InvalidParams` (NOT `-32601 MethodNotFound`)
3. **`tools` capability not declared** → `-32601 MethodNotFound`
4. **Server doesn't support tool calls** → `-32601 MethodNotFound`

Per 2026-07-28 schema comment on `InvalidParamsError` (-32602):
> "**Tools**: Unknown tool name or invalid tool arguments"

This is explicitly NOT -32601.

### `isError` Semantics
- `isError: true` means the tool ran but the invocation produced an error
- LLM sees the error content and can self-correct
- `isError: false` (or absent) = success
- Do NOT throw JSON-RPC errors for tool-level failures

### `outputSchema` Evolution
- **2025-11-25**: Restricted to `{ type: "object", ... }` at root level
- **2026-07-28**: Any valid JSON Schema 2020-12 (`outputSchema?: { $schema?: string; [key: string]: unknown }`)
- `structuredContent` in 2026-07-28 is `unknown` (any JSON value, not just object)

### ToolAnnotations (Hints Only)
```typescript
interface ToolAnnotations {
  title?: string;           // display name (precedence: title > annotations.title > name)
  readOnlyHint?: boolean;   // default: false
  destructiveHint?: boolean;// default: true
  idempotentHint?: boolean; // default: false
  openWorldHint?: boolean;  // default: true
}
```
**These are HINTS, not guarantees.** Clients MUST NOT make security decisions based on them.

### Conformance Test Scenarios
| Scenario | Description |
|----------|-------------|
| `tools-list` | Lists tools; validates inputSchema |
| `tools-call-simple-text` | Returns `{"type":"text","text":"..."}` |
| `tools-call-image` | Returns image content block |
| `tools-call-audio` | Returns audio content block |
| `tools-call-embedded-resource` | Returns embedded resource |
| `tools-call-mixed-content` | Returns multiple content types |
| `tools-call-error` | Returns `isError: true` |
| `json-schema-2020-12` | Tool with `$schema` + `$defs` + `additionalProperties` (SEP-1613) |

### Gotchas / Advice
- **`content` array is required even when `structuredContent` is present** — unstructured content is the primary representation.
- **Unknown tool → -32602, not -32601** — this is a CRITICAL and non-obvious requirement. mcptools likely gets this wrong.
- **`annotations.title` vs `Tool.title`**: Display precedence is `Tool.title > annotations.title > Tool.name`. Both exist for backward compat.
- **JSON Schema 2020-12 default** — if `$schema` is absent from `inputSchema`, it defaults to JSON Schema 2020-12. SDKs that hardcode draft-07 behavior break SEP-1613.
- **Binary/audio content**: `data` is standard base64, not URL-safe. `mimeType` is required.
- **`ResourceLink` in tool results** is NOT guaranteed to appear in `resources/list` — spec explicitly notes this.
- **`EmbeddedResource.type` is `"resource"`** — same as in prompts. Don't confuse with `ResourceLink.type = "resource_link"`.
- **`Annotations.lastModified`** format: ISO 8601 string (e.g., `"2025-01-12T15:00:58Z"`).

---

## Cross-Cutting Concerns

### Version Negotiation (2025-11-25 Stateful)
1. Client sends `protocolVersion: "2025-11-25"` in initialize
2. Server responds with the version it supports (may be lower)
3. If client can't support server's version → client MUST disconnect
4. Supported versions in the codebase: 2024-11-05, 2025-03-26, 2025-06-18, 2025-11-25

### Version Negotiation (2026-07-28 Stateless)
1. Client sends `MCP-Protocol-Version: 2026-07-28` header AND `_meta["io.modelcontextprotocol/protocolVersion"]: "2026-07-28"`
2. If mismatch between header and body → -32020 HeaderMismatch
3. If unsupported version → -32022 UnsupportedProtocolVersion with `data.supported` array
4. Client can call `server/discover` first to learn what versions the server supports

### Pagination (Cursor-Based)
- Cursor is an **opaque string** — implementation-defined encoding
- Absent `cursor` in request = first page
- Absent `nextCursor` in result = last page
- Expired/invalid cursor → -32602 InvalidParams
- Cursors are NOT guaranteed stable across server restarts

### `_meta` Field
- Optional additional metadata on requests, responses, notifications
- Key naming rules (2026-07-28): `[prefix/]name` format; prefix uses reverse DNS; `io.modelcontextprotocol/` and `dev.mcp/` are reserved
- Clients and servers MUST NOT make assumptions about unknown `_meta` keys

---

## Conformance Test Command Reference

```bash
# Run all server scenarios (2025-11-25)
npx @modelcontextprotocol/conformance server --url http://localhost:3000/mcp

# Run for specific spec version
npx @modelcontextprotocol/conformance server --url http://localhost:3000/mcp --spec-version 2025-11-25

# Run stateless (2026-07-28) scenarios
npx @modelcontextprotocol/conformance server --url http://localhost:3000/mcp --spec-version 2026-07-28

# Run specific scenario
npx @modelcontextprotocol/conformance server --url http://localhost:3000/mcp --scenario elicitation-sep1034-defaults

# Run elicitation scenarios
npx @modelcontextprotocol/conformance server --url http://localhost:3000/mcp --scenario elicitation-sep1034-defaults
npx @modelcontextprotocol/conformance server --url http://localhost:3000/mcp --scenario elicitation-sep1330-enums
```

---

## Key SDK PRs for Reference

| PR | Repo | Feature |
|----|------|---------|
| modelcontextprotocol/typescript-sdk#2184 | typescript-sdk | SEP-2575 stateless lifecycle |
| modelcontextprotocol/typescript-sdk#2434 | typescript-sdk | Reject duplicate in-flight request IDs in Streamable HTTP |
| modelcontextprotocol/typescript-sdk#2174 | typescript-sdk | Fix streamable HTTP transport restart after close |
| modelcontextprotocol/typescript-sdk#2578 | typescript-sdk | MRTR app-rendered elicitation example (draft) |
| modelcontextprotocol/python-sdk#2804 | python-sdk | SEP-2575 stateless lifecycle |
| modelcontextprotocol/python-sdk#3063 | python-sdk | Reject duplicate in-flight request IDs |
| modelcontextprotocol/modelcontextprotocol#2575 | spec | SEP-2575: Make MCP Stateless |
| modelcontextprotocol/modelcontextprotocol#3039 | spec | Docs: reflect stateless protocol |
| modelcontextprotocol/modelcontextprotocol#3159 | spec | Docs: post-final SEP-2575 changes |
| modelcontextprotocol/modelcontextprotocol#3002 | spec | Make clientInfo optional, serverInfo to _meta |
| modelcontextprotocol/modelcontextprotocol#2953 | spec | subscriptions/listen result for graceful closure |

---

## Suggested Build Order & Parallelization

### Phase 1 — Fully Independent (can be built in parallel)

These feature areas share no code and have no ordering dependencies:

| Workstream A | Workstream B | Workstream C |
|---|---|---|
| **Resources** (list, read, templates, subscribe/unsubscribe) | **Prompts** (list, get + all content types) | **Completion** (complete, both ref types) |

**Rationale:** Resources need their own storage/routing. Prompts have their own message assembly. Completion is a thin autocomplete layer over prompt/template lookup. All three are pure server-side features with no client-capability negotiation complexity.

### Phase 2 — After Phase 1, Also Parallelizable

| Workstream D | Workstream E |
|---|---|
| **Logging** (setLevel + notifications/message) | **Progress + Cancellation** (progressToken extraction, notification dispatch, cancel handler) |

**Rationale:** Logging requires the notification dispatch infrastructure, but it's otherwise independent. Progress requires the SSE/stream infrastructure already built for resources.

### Phase 3 — Sequential (each depends on prior phases)

1. **Streamable HTTP Transport** — must be done before elicitation/sampling because the SSE multiplexing is needed to carry server-to-client requests. DNS rebinding protection goes here too.

2. **structuredContent + Tool Schemas** — depends on the tool dispatch infrastructure. Build after transport layer is solid.

3. **Elicitation** (2025-11-25 mode) — depends on transport (SSE stream must be open), must come after structuredContent work is stable. Implement the `test_elicitation_sep1034_defaults` and `test_elicitation_sep1330_enums` tools.

4. **Sampling** (2025-11-25 mode) — depends on the same SSE multiplexing as elicitation. Can be parallelized with elicitation.

5. **Roots** — depends on transport (server-to-client request). Can be parallelized with elicitation/sampling.

### Phase 4 — Optional/2026-07-28 Only

| Feature | Dependencies |
|---------|-------------|
| **Stateless lifecycle** (server/discover, per-request _meta) | Requires all Phase 1-3 features to be rearchitected |
| **subscriptions/listen** | Requires stateless lifecycle |
| **MRTR (InputRequiredResult)** | Requires elicitation + sampling + stateless lifecycle |

### Dependency Graph Summary

```
Resources ─┐
Prompts ────┤
Completion ─┤─→ Logging ──┐
            │   Progress ──┤─→ Streamable HTTP ─→ structuredContent ─→ Elicitation ─→ Sampling ─→ Roots
            │              │                                            └─────────────→ Sampling (parallel)
            └──────────────┘

For 2026-07-28 only:
Streamable HTTP → Stateless Lifecycle → subscriptions/listen → MRTR
```

### What's Safe to Parallelize Right Now (for R SDK fork)
1. **Session A**: Resources + binary blob handling + pagination cursor
2. **Session B**: Prompts (all content types) + completion
3. **Session C**: Logging + basic notification infrastructure
4. **Session D**: Progress token extraction + cancellation handler
5. **After A-D merge**: Session E for Streamable HTTP transport; Session F for tool content types + outputSchema + isError semantics
6. **After E-F merge**: Session G for elicitation (SEP-1034 + SEP-1330); Session H for sampling
```

---

## Summary of Biggest Gotchas

**Found during research — these are the most impactful implementation traps:**

1. **Unknown tool name is -32602, NOT -32601** (`modelcontextprotocol/modelcontextprotocol:schema/2026-07-28/schema.ts` — `InvalidParamsError` comment explicitly names "Unknown tool name"; `MethodNotFoundError` is for unsupported methods/capabilities). mcptools almost certainly returns -32601 here.

2. **Elicitation requires flat schema only** — no nested objects. `requestedSchema.properties` values are `PrimitiveSchemaDefinition`, not arbitrary JSON Schema.

3. **SEP-1034 default values for enum must be a valid enum member** — conformance test validates this explicitly.

4. **SEP-1330 titled single-select uses `oneOf` (not `enum`)** but untitled uses `enum`. Titled multi-select uses `items.anyOf` (not `items.oneOf`). Easy to mix up.

5. **2026-07-28 `resultType` is required in ALL results** — absent = backward compat (treat as "complete"), but implementing servers must include it.

6. **`subscriptions/listen` acknowledged notification MUST be first** — no other notifications before it, even on stdio where streams interleave.

7. **`subscriptions/listen` replaces both GET SSE endpoint AND `resources/subscribe`/`resources/unsubscribe`** — three separate 2025-11-25 mechanisms collapse into one in 2026-07-28.

8. **Sampling `maxTokens` is required** (not optional), and `SamplingMessage.content` is `Block | Block[]` (both shapes must be handled in deserialization).

9. **DNS rebinding protection**: Must check `Host` OR `Origin` header on localhost. Advisory GHSA-w48q-cv73-mx4w shows this is a real exploit vector.

10. **`server/discover` is REQUIRED in 2026-07-28** — `Servers MUST implement server/discover` (per scenario description for `server-stateless`).

11. **`io.modelcontextprotocol/clientInfo` is SHOULD** — servers must NOT reject requests that omit it (PR#3002 change after SEP-2575 was finalized).

12. **Binary content** (`blob`, `data`) must be standard base64 (not URL-safe). Mimetypes are required on binary content.

13. **`isError: true` keeps the LLM in the loop** — if you throw a JSON-RPC error for tool failures, the LLM never sees the error and cannot self-correct.

14. **Caching (SEP-2549)**: In 2026-07-28, `ttlMs` and `cacheScope` are required fields on all list results and `ReadResourceResult`. Forgetting them is a wire-schema violation.

15. **Duplicate request IDs** in Streamable HTTP: Server must reject a POST containing an already-in-flight request ID with HTTP 400 + -32600. But sequential reuse after completion is allowed (typescript-sdk PR#2434).

---

## Citations

- Schema (2025-11-25): `modelcontextprotocol/modelcontextprotocol:schema/2025-11-25/schema.ts`
- Schema (2026-07-28): `modelcontextprotocol/modelcontextprotocol:schema/2026-07-28/schema.ts`
- Conformance scenarios index: `modelcontextprotocol/conformance:src/scenarios/index.ts`
- Elicitation defaults conformance: `modelcontextprotocol/conformance:src/scenarios/server/elicitation-defaults.ts`
- Elicitation enums conformance: `modelcontextprotocol/conformance:src/scenarios/server/elicitation-enums.ts`
- Resources conformance: `modelcontextprotocol/conformance:src/scenarios/server/resources.ts`
- DNS rebinding conformance: `modelcontextprotocol/conformance:src/scenarios/server/dns-rebinding.ts`
- Stateless conformance: `modelcontextprotocol/conformance:src/scenarios/server/stateless.ts`
- SEP-2575 tracking: `modelcontextprotocol/modelcontextprotocol#2884`
- SEP-2575 post-final changes: `modelcontextprotocol/modelcontextprotocol#3159`
- SEP-1034 (conformance ref): `modelcontextprotocol/modelcontextprotocol#1034`
- SEP-1330 (conformance ref): `modelcontextprotocol/modelcontextprotocol#1330`
- TypeScript SDK stateless: `modelcontextprotocol/typescript-sdk#2184`
- TypeScript SDK duplicate IDs: `modelcontextprotocol/typescript-sdk#2434`
- Python SDK stateless: `modelcontextprotocol/python-sdk#2804`
- Ruby SDK tier assessment (full conformance scenario list): `modelcontextprotocol/modelcontextprotocol#3127`
