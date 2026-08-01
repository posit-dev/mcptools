# MCP Everything-Server Conformance Contract

> **Source ground truth:** `/tmp/conformance/` (official conformance suite)  
> **Reference implementation:** `/tmp/conformance/examples/servers/typescript/everything-server.ts`  
> **Spec versions covered:** `2025-06-18`, `2025-11-25`, `2026-07-28` (draft)

---

## 1. Core / Lifecycle

### 1.1 `server-initialize` (introduced `2025-06-18`, removed in draft)

**Source:** `src/scenarios/server/lifecycle.ts:25-186`

**Methods exercised (in order):**
1. `POST /mcp` → `initialize` (no `MCP-Session-Id` header)
2. `POST /mcp` → `notifications/initialized` (with `MCP-Session-Id` header)

**Request shape:**
```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2025-11-25",
    "capabilities": {},
    "clientInfo": { "name": "conformance-session-id-test", "version": "1.0.0" }
  }
}
```

**Required server response:**
- HTTP 200 with JSON or SSE containing `result.protocolVersion`, `result.capabilities`, `result.serverInfo`
- `MCP-Session-Id` response header (optional but if set MUST contain only visible ASCII chars `0x21–0x7E`)

**Checks asserted:**
- `server-initialize`: Connection completes (SUCCESS if no exception)
- `server-session-id-visible-ascii`: If `MCP-Session-Id` header present, validate charset `/^[\x21-\x7E]+$/`

**Required capabilities advertised in `initialize` result:**
```json
{
  "tools":     { "listChanged": true },
  "resources": { "subscribe": true, "listChanged": true },
  "prompts":   { "listChanged": true },
  "logging":   {},
  "completions": {}
}
```
**Source:** `everything-server.ts:209-230`

---

### 1.2 `ping` (introduced `2025-06-18`, removed in draft)

**Source:** `src/scenarios/server/utils.ts:97-188`

**Methods exercised:** `ping`

**Required response:** `{}` (empty JSON object)

**Check asserted:** `result` must be empty (`Object.keys(result).length === 0`)

---

### 1.3 `logging-set-level` (introduced `2025-06-18`, removed in draft)

**Source:** `src/scenarios/server/utils.ts:13-95`

**Methods exercised:** `logging/setLevel`

**Request params:** `{ "level": "info" }`

**Required response:** `{}` (empty object)

**Log levels supported:** `debug | info | notice | warning | error | critical | alert | emergency`

**Server implementation (`everything-server.ts:1089-1096`):**
```typescript
mcpServer.server.setRequestHandler(
  z.object({ method: z.literal('logging/setLevel') }).passthrough(),
  async (request: any) => {
    const level = request.params.level;
    sendLog('info', `Log level set to: ${level}`);
    return {};
  }
);
```

---

### 1.4 `completion-complete` (introduced `2025-06-18`)

**Source:** `src/scenarios/server/utils.ts:190-303`

**Methods exercised:** `completion/complete`

**Request params:**
```json
{
  "ref": { "type": "ref/prompt", "name": "test_prompt_with_arguments" },
  "argument": { "name": "arg1", "value": "test" }
}
```

**Required response shape:**
```json
{
  "completion": {
    "values": [],
    "total": 0,
    "hasMore": false
  }
}
```

**Check asserted:** `result.completion` exists and `result.completion.values` is an array (may be empty).

**Server implementation (`everything-server.ts:1100-1113`):**
```typescript
mcpServer.server.setRequestHandler(
  z.object({ method: z.literal('completion/complete') }).passthrough(),
  async (_request: any) => {
    return { completion: { values: [], total: 0, hasMore: false } };
  }
);
```

**Required capability:** `completions: {}` in initialize result.

---

## 2. Tools

### Tool Name Format (SEP-986)

**Source:** `src/scenarios/server/tools.ts:24-46`

- Pattern: `/^[A-Za-z0-9_./-]+$/`
- Length: 1–64 characters
- Check ID: `tools-name-format`

---

### 2.1 `tools-list` (introduced `2025-06-18`)

**Methods exercised:** `tools/list`

**Each tool MUST have:**
- `name` (string, 1–64 chars, `/^[A-Za-z0-9_./-]+$/`)
- `description` (string)
- `inputSchema` (valid JSON Schema object)

**Check IDs:** `tools-list`, `tools-name-format`

---

### 2.2 `tools-call-simple-text` (introduced `2025-06-18`)

**Source:** `src/scenarios/server/tools.ts:188-271`

**Fixture:** Tool `test_simple_text`, no arguments.

**Required response:**
```json
{
  "content": [
    { "type": "text", "text": "This is a simple text response for testing." }
  ]
}
```

**Checks:** content array non-empty, at least one `type: "text"` item with non-empty `text` field.

**Server implementation (`everything-server.ts:302-314`):**
```typescript
mcpServer.tool('test_simple_text', 'Tests simple text content response', {}, async () => {
  return { content: [{ type: 'text', text: 'This is a simple text response for testing.' }] };
});
```

---

### 2.3 `tools-call-image` (introduced `2025-06-18`)

**Source:** `src/scenarios/server/tools.ts:273-359`

**Fixture:** Tool `test_image_content`, no required arguments.

**Required response:**
```json
{
  "content": [
    { "type": "image", "data": "<base64-png>", "mimeType": "image/png" }
  ]
}
```

**Magic value (1×1 red pixel PNG):**
```
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==
```
**Source:** `everything-server.ts:159-160`

**Checks:** `imageContent.data` non-empty, `imageContent.mimeType` non-empty.

---

### 2.4 `tools-call-audio` (introduced `2025-06-18`)

**Source:** `src/scenarios/server/tools.ts:1028-1121`

**Fixture:** Tool `test_audio_content`, no arguments.

**Required response:**
```json
{
  "content": [
    { "type": "audio", "data": "<base64-wav>", "mimeType": "audio/wav" }
  ]
}
```

**Magic value (minimal WAV):**
```
UklGRiYAAABXQVZFZm10IBAAAAABAAEAQB8AAAB9AAACABAAZGF0YQIAAAA=
```
**Source:** `everything-server.ts:162-164`

**Checks:** mimeType MUST be exactly `"audio/wav"` (`tools.ts:1077-1079`)

---

### 2.5 `tools-call-embedded-resource` (introduced `2025-06-18`)

**Source:** `src/scenarios/server/tools.ts:1123-1210`

**Fixture:** Tool `test_embedded_resource`, no arguments.

**Required response:**
```json
{
  "content": [
    {
      "type": "resource",
      "resource": {
        "uri": "test://embedded-resource",
        "mimeType": "text/plain",
        "text": "This is an embedded resource content."
      }
    }
  ]
}
```

**Checks:** `resource.uri`, `resource.mimeType`, and either `resource.text` or `resource.blob` must be present.

---

### 2.6 `tools-call-mixed-content` (introduced `2025-06-18`)

**Source:** `src/scenarios/server/tools.ts:361-460`

**Fixture:** Tool `test_multiple_content_types`, no arguments.

**Required response (all 3 content types):**
```json
{
  "content": [
    { "type": "text", "text": "Multiple content types test:" },
    { "type": "image", "data": "<base64-png>", "mimeType": "image/png" },
    {
      "type": "resource",
      "resource": {
        "uri": "test://mixed-content-resource",
        "mimeType": "application/json",
        "text": "{\"test\":\"data\",\"value\":123}"
      }
    }
  ]
}
```

**Checks:** content array must have ≥2 items, must include at least one each of `type: "text"`, `type: "image"`, `type: "resource"`.

---

### 2.7 `tools-call-with-logging` (introduced `2025-06-18`, removed in draft)

**Source:** `src/scenarios/server/tools.ts:462-553`

**Fixture:** Tool `test_tool_with_logging`, no arguments.

**Behavior:** During execution send exactly 3 `notifications/message` at `"info"` level:
1. `"Tool execution started"`
2. `"Tool processing data"` (after ~50 ms delay)
3. `"Tool execution completed"` (after another ~50 ms delay)

**Return:** `{ "content": [{ "type": "text", "text": "Tool with logging executed successfully" }] }`

**Setup:** Client must call `logging/setLevel` with `"debug"` before calling tool.

**Checks:** `logNotifications.length >= 3` (from `notifications/message` events).

**Notification format:**
```json
{
  "jsonrpc": "2.0",
  "method": "notifications/message",
  "params": { "level": "info", "data": "Tool execution started" }
}
```
**Source:** `everything-server.ts:400-432`

---

### 2.8 `tools-call-error` (introduced `2025-06-18`)

**Source:** `src/scenarios/server/tools.ts:555-638`

**Fixture:** Tool `test_error_handling`, no arguments.

**Required response (NOT a JSON-RPC error — must be a successful RPC with `isError: true`):**
```json
{
  "isError": true,
  "content": [
    { "type": "text", "text": "This tool intentionally returns an error for testing" }
  ]
}
```

**Important:** The SDK converts a thrown `Error` into `isError: true` automatically. The check asserts `result.isError === true` and `result.content[0].text` is truthy.

**Server implementation (`everything-server.ts:483-491`):**
```typescript
mcpServer.registerTool('test_error_handling', { description: 'Tests error response handling' }, async () => {
  throw new Error('This tool intentionally returns an error for testing');
});
```

---

### 2.9 `tools-call-with-progress` (introduced `2025-06-18`)

**Source:** `src/scenarios/server/tools.ts:640-759`

**Fixture:** Tool `test_tool_with_progress`, no required arguments.

**Request shape includes `_meta.progressToken`:**
```json
{
  "name": "test_tool_with_progress",
  "arguments": {},
  "_meta": { "progressToken": "progress-test-1" }
}
```

**Required behavior:** Send exactly 3 `notifications/progress` in order:
```json
{ "method": "notifications/progress", "params": { "progressToken": "progress-test-1", "progress": 0, "total": 100, "message": "Completed step 0 of 100" } }
{ "method": "notifications/progress", "params": { "progressToken": "progress-test-1", "progress": 50, "total": 100, "message": "Completed step 50 of 100" } }
{ "method": "notifications/progress", "params": { "progressToken": "progress-test-1", "progress": 100, "total": 100, "message": "Completed step 100 of 100" } }
```

**Return:** `{ "content": [{ "type": "text", "text": "<progressToken value as string>" }] }`

**Checks:** ≥3 progress notifications, progressToken matches `"progress-test-1"`, values non-decreasing (0 ≤ 50 ≤ 100).

**Source:** `everything-server.ts:434-480`

---

### 2.10 `tools-call-sampling` (introduced `2025-06-18`, removed in draft)

**Source:** `src/scenarios/server/tools.ts:761-891`

**Fixture:** Tool `test_sampling` with argument `prompt` (string, required).

**Behavior:** Server issues `sampling/createMessage` to client:
```json
{
  "method": "sampling/createMessage",
  "params": {
    "messages": [{ "role": "user", "content": { "type": "text", "text": "<prompt arg>" } }],
    "maxTokens": 100
  }
}
```

**The conformance test client responds with:**
```json
{ "role": "assistant", "content": { "type": "text", "text": "This is a test response from the client" }, "model": "test-model", "stopReason": "endTurn" }
```

**Server returns:** `{ "content": [{ "type": "text", "text": "LLM response: This is a test response from the client" }] }`

**Checks:** `samplingRequested === true`, content array non-empty.

**Source:** `everything-server.ts:533-591`

---

### 2.11 `tools-call-elicitation` (introduced `2025-06-18`, removed in draft)

**Source:** `src/scenarios/server/tools.ts:893-1026`

**Fixture:** Tool `test_elicitation` with argument `message` (string, required).

**Behavior:** Server issues `elicitation/create` to client:
```json
{
  "method": "elicitation/create",
  "params": {
    "message": "<message arg>",
    "requestedSchema": {
      "type": "object",
      "properties": {
        "response": { "type": "string", "description": "User's response" }
      },
      "required": ["response"]
    }
  }
}
```

> **Note:** The scenario description (line 920) shows `username` and `email` fields, but the actual server implementation (line 609-619) uses a `response` field only. The conformance client test handler accepts any schema and returns `{ action: "accept", content: { username: "testuser", email: "test@example.com" } }`.

**Server returns:** `{ "content": [{ "type": "text", "text": "User response: action=accept, content={...}" }] }`

**Checks:** `elicitationRequested === true`, content array non-empty.

**Source:** `everything-server.ts:593-645`

---

### 2.12 `json-schema-2020-12` (introduced `2025-11-25`)

**Source:** `src/scenarios/server/json-schema-2020-12.ts:88-352`

**Fixture:** Tool `json_schema_2020_12_tool`.

**The inputSchema returned by `tools/list` MUST be exactly:**
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "$defs": {
    "address": {
      "$anchor": "addressDef",
      "type": "object",
      "properties": {
        "street": { "type": "string" },
        "city": { "type": "string" }
      }
    }
  },
  "properties": {
    "name": { "type": "string" },
    "address": { "$ref": "#/$defs/address" },
    "contactMethod": { "type": "string", "enum": ["phone", "email"] },
    "phone": { "type": "string" },
    "email": { "type": "string" }
  },
  "allOf": [{ "anyOf": [{ "required": ["phone"] }, { "required": ["email"] }] }],
  "if": { "properties": { "contactMethod": { "const": "phone" } }, "required": ["contactMethod"] },
  "then": { "required": ["phone"] },
  "else": { "required": ["email"] },
  "additionalProperties": false
}
```
**Source:** `everything-server.ts:169-205`, `json-schema-2020-12.ts:36-64`

**Checks asserted (in order):**
1. `json-schema-2020-12-tool-found`: tool `json_schema_2020_12_tool` exists in `tools/list`
2. `json-schema-2020-12-$schema`: `inputSchema.$schema === "https://json-schema.org/draft/2020-12/schema"` (MUST for all versions)
3. `json-schema-2020-12-$defs`: `inputSchema.$defs.address` exists (MUST)
4. `json-schema-2020-12-additionalProperties`: `inputSchema.additionalProperties === false` (MUST)
5. `sep-2106-composition-keywords-preserved`: `inputSchema.allOf` with nested `anyOf` (FAILURE only on `2026-07-28`, SKIPPED on earlier)
6. `sep-2106-conditional-keywords-preserved`: `if/then/else` present (same gating)
7. `sep-2106-anchor-keyword-preserved`: `$defs.address.$anchor` present (same gating)

**Implementation note:** The server overrides `tools/list` to return the raw JSON Schema object for this tool only; other tools use Zod-converted schemas. (`everything-server.ts:1120-1172`)

---

## 3. Resources

### 3.1 `resources-list` (introduced `2025-06-18`)

**Methods:** `resources/list`

**Each resource MUST have:** `uri`, `name` (description optional but recommended).

**Required resources (from `everything-server.ts:854-970`):**
| Name | URI | mimeType |
|------|-----|----------|
| `static-text` | `test://static-text` | `text/plain` |
| `static-binary` | `test://static-binary` | `image/png` |
| `watched-resource` | `test://watched-resource` | `text/plain` |

**Template:** `test://template/{id}/data` (listed via `resources/templates/list`, not `resources/list`)

---

### 3.2 `resources-read-text` (introduced `2025-06-18`)

**Methods:** `resources/read` with `{ "uri": "test://static-text" }`

**Required response:**
```json
{
  "contents": [
    {
      "uri": "test://static-text",
      "mimeType": "text/plain",
      "text": "This is the content of the static text resource."
    }
  ]
}
```

**Checks:** `contents[0].uri`, `contents[0].mimeType`, `contents[0].text` all non-empty.

---

### 3.3 `resources-read-binary` (introduced `2025-06-18`)

**Methods:** `resources/read` with `{ "uri": "test://static-binary" }`

**Required response:**
```json
{
  "contents": [
    {
      "uri": "test://static-binary",
      "mimeType": "image/png",
      "blob": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
    }
  ]
}
```

**Checks:** `contents[0].blob` non-empty (binary field, not `text`).

---

### 3.4 `resources-templates-read` (introduced `2025-06-18`)

**Methods:** `resources/read` with `{ "uri": "test://template/123/data" }`

**Template:** `test://template/{id}/data` (RFC 6570 URI template)

**Required response:**
```json
{
  "contents": [
    {
      "uri": "test://template/123/data",
      "mimeType": "application/json",
      "text": "{\"id\":\"123\",\"templateTest\":true,\"data\":\"Data for ID: 123\"}"
    }
  ]
}
```

**Check:** `contents[0].text` must include the string `"123"` (parameter substitution verified).

**Server implementation (`everything-server.ts:900-927`):**
```typescript
mcpServer.registerResource('template', new ResourceTemplate('test://template/{id}/data', { list: undefined }), ...,
  async (uri, variables) => {
    const id = variables.id;
    return { contents: [{ uri: uri.toString(), mimeType: 'application/json',
      text: JSON.stringify({ id, templateTest: true, data: `Data for ID: ${id}` }) }] };
  }
);
```

---

### 3.5 `resources-subscribe` (introduced `2025-06-18`, removed in draft)

**Methods:** `resources/subscribe` with `{ "uri": "test://watched-resource" }`

**Required response:** `{}` (empty object)

**Required capability:** `resources.subscribe: true` in initialize.

---

### 3.6 `resources-unsubscribe` (introduced `2025-06-18`, removed in draft)

**Source:** `src/scenarios/server/resources.ts:604-672`

**Methods (in order):**
1. `resources/subscribe` with `{ "uri": "test://watched-resource" }`
2. `resources/unsubscribe` with `{ "uri": "test://watched-resource" }`

**Required response for unsubscribe:** `{}` (empty object)

---

## 4. Prompts

### 4.1 `prompts-list` (introduced `2025-06-18`)

**Methods:** `prompts/list`

**Each prompt MUST have:** `name`, `description`. `arguments` array is optional.

**Required prompts (from `everything-server.ts:972-1085`):**
| Name | Arguments |
|------|-----------|
| `test_simple_prompt` | none |
| `test_prompt_with_arguments` | `arg1` (string), `arg2` (string) |
| `test_prompt_with_embedded_resource` | `resourceUri` (string) |
| `test_prompt_with_image` | none |

---

### 4.2 `prompts-get-simple` (introduced `2025-06-18`)

**Methods:** `prompts/get` with `{ "name": "test_simple_prompt" }`

**Required response:**
```json
{
  "messages": [
    {
      "role": "user",
      "content": { "type": "text", "text": "This is a simple prompt for testing." }
    }
  ]
}
```

**Checks:** messages non-empty, each message has `role` and `content`.

---

### 4.3 `prompts-get-with-args` (introduced `2025-06-18`)

**Methods:** `prompts/get` with:
```json
{ "name": "test_prompt_with_arguments", "arguments": { "arg1": "testValue1", "arg2": "testValue2" } }
```

**Required response must include both argument values in message text:**
```json
{
  "messages": [
    {
      "role": "user",
      "content": { "type": "text", "text": "Prompt with arguments: arg1='testValue1', arg2='testValue2'" }
    }
  ]
}
```

**Checks:** `JSON.stringify(result.messages)` includes `"testValue1"` AND `"testValue2"`.

---

### 4.4 `prompts-get-embedded-resource` (introduced `2025-06-18`)

**Methods:** `prompts/get` with:
```json
{ "name": "test_prompt_with_embedded_resource", "arguments": { "resourceUri": "test://example-resource" } }
```

**Required response:**
```json
{
  "messages": [
    {
      "role": "user",
      "content": {
        "type": "resource",
        "resource": {
          "uri": "test://example-resource",
          "mimeType": "text/plain",
          "text": "Embedded resource content for testing."
        }
      }
    },
    {
      "role": "user",
      "content": { "type": "text", "text": "Please process the embedded resource above." }
    }
  ]
}
```

**Check:** At least one message with `content.type === "resource"` OR `content.resource !== undefined`.

---

### 4.5 `prompts-get-with-image` (introduced `2025-06-18`)

**Methods:** `prompts/get` with `{ "name": "test_prompt_with_image" }`

**Required response:**
```json
{
  "messages": [
    {
      "role": "user",
      "content": {
        "type": "image",
        "data": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==",
        "mimeType": "image/png"
      }
    },
    {
      "role": "user",
      "content": { "type": "text", "text": "Please analyze the image above." }
    }
  ]
}
```

**Check:** At least one message with `content.type === "image"` AND `content.data` AND `content.mimeType`.

---

## 5. Elicitation

### 5.1 `elicitation-sep1034-defaults` (introduced `2025-11-25`, removed in draft)

**Source:** `src/scenarios/server/elicitation-defaults.ts`

**Fixture:** Tool `test_elicitation_sep1034_defaults`, no arguments.

**Behavior:** Server sends `elicitation/create` with this EXACT schema:
```json
{
  "type": "object",
  "properties": {
    "name":     { "type": "string",  "description": "User name",          "default": "John Doe" },
    "age":      { "type": "integer", "description": "User age",           "default": 30 },
    "score":    { "type": "number",  "description": "User score",         "default": 95.5 },
    "status":   { "type": "string",  "description": "User status",        "enum": ["active","inactive","pending"], "default": "active" },
    "verified": { "type": "boolean", "description": "Verification status","default": true }
  },
  "required": []
}
```

**Message:** `"Please review and update the form fields with defaults"`

**Checks (each field validated separately):**
- `name`: `type === "string"`, `default === "John Doe"`
- `age`: `type === "integer"`, `default === 30`
- `score`: `type === "number"`, `default === 95.5`
- `status`: `type === "string"`, `enum` array present, `default === "active"` (must be valid enum member)
- `verified`: `type === "boolean"`, `default === true`

**Source:** `everything-server.ts:648-719`

---

### 5.2 `elicitation-sep1330-enums` (introduced `2025-11-25`, removed in draft)

**Source:** `src/scenarios/server/elicitation-enums.ts`

**Fixture:** Tool `test_elicitation_sep1330_enums`, no arguments.

**Behavior:** Server sends `elicitation/create` with schema containing all 5 enum variants:

```json
{
  "type": "object",
  "properties": {
    "untitledSingle": { "type": "string", "description": "Select one option", "enum": ["option1","option2","option3"] },
    "titledSingle":   { "type": "string", "description": "Select one option with titles", "oneOf": [
      { "const": "value1", "title": "First Option" },
      { "const": "value2", "title": "Second Option" },
      { "const": "value3", "title": "Third Option" }
    ]},
    "legacyEnum": { "type": "string", "description": "Select one option (legacy)", "enum": ["opt1","opt2","opt3"], "enumNames": ["Option One","Option Two","Option Three"] },
    "untitledMulti": { "type": "array", "description": "Select multiple options", "minItems": 1, "maxItems": 3,
      "items": { "type": "string", "enum": ["option1","option2","option3"] } },
    "titledMulti": { "type": "array", "description": "Select multiple options with titles", "minItems": 1, "maxItems": 3,
      "items": { "anyOf": [
        { "const": "value1", "title": "First Choice" },
        { "const": "value2", "title": "Second Choice" },
        { "const": "value3", "title": "Third Choice" }
      ]}}
  },
  "required": []
}
```

**Checks (one per variant):**
- `untitledSingle`: has `enum` array, NO `oneOf`, NO `enumNames`
- `titledSingle`: has `oneOf` with `const`/`title` pairs, NO `enum` array
- `legacyEnum`: has both `enum` AND `enumNames` of same length
- `untitledMulti`: `type: "array"`, `items.type: "string"`, `items.enum` array, NO `items.anyOf`
- `titledMulti`: `type: "array"`, `items.anyOf` with `const`/`title` pairs, NO `items.enum`

**Source:** `everything-server.ts:721-816`

---

## 6. Sampling

### See `tools-call-sampling` above (section 2.10)

The `test_sampling` tool must issue `sampling/createMessage` as a server→client request. The client registers a handler that returns a mock response; the server echoes it back as text content.

---

## 7. Progress

### See `tools-call-with-progress` above (section 2.9)

The `test_tool_with_progress` tool must:
1. Read `_meta.progressToken` from the tool call request
2. Emit 3 `notifications/progress` events on that token
3. Return the progressToken string as text content

---

## 8. SSE / Transport

### 8.1 `server-sse-polling` (introduced `2025-11-25`, removed in draft)

**Source:** `src/scenarios/server/sse-polling.ts:74-end`

**Mechanism:** Uses `test_reconnection` tool (already registered) that intentionally closes the SSE stream mid-call.

**Fixture:** Tool `test_reconnection`, no arguments.

**Behavior:**
1. Client POSTs `tools/call` with `{ name: "test_reconnection" }`
2. Server calls `transport.closeSSEStream(requestId)` to close the SSE stream mid-call
3. Client reconnects using SSE `Last-Event-ID` (SEP-1699)
4. Server completes the tool after 100ms and delivers result via the new SSE stream

**Return:** `{ "content": [{ "type": "text", "text": "Reconnection test completed successfully. ..." }] }`

**SEP-1699 requirements:**
- SSE priming events include `event id` and may include `retry` field
- `eventStore` must be implemented for replay
- On GET with `Last-Event-ID`, replay missed events
- `retryInterval: 5000` (5s) in transport config

**Server implementation (`everything-server.ts:493-531, 2343-2367`):**
```typescript
new StreamableHTTPServerTransport({
  sessionIdGenerator: () => randomUUID(),
  eventStore: createEventStore(),  // in-memory replay store
  retryInterval: 5000,
  ...
});
```

---

### 8.2 `server-sse-multiple-streams` (introduced `2025-11-25`)

**Source:** `src/scenarios/server/sse-multiple-streams.ts`

**Mechanism:** Client sends 3 concurrent POST requests for `tools/list`, each must get its own response.

**Test:**
- 3 simultaneous POST requests with `id: 1000`, `1001`, `1002` to `/mcp`
- All must return HTTP 200
- Each may return JSON or SSE stream
- Content types collected and validated

**Requirements:**
- Server MUST handle concurrent POST requests on the same session
- Each POST request gets its own independent stream
- Multiple SSE streams per session are allowed

---

## 9. DNS Rebinding Protection

### 9.1 `dns-rebinding-protection` (introduced `2025-11-25`)

**Source:** `src/scenarios/server/dns-rebinding.ts`

**Applies to:** Localhost servers only (`localhost`, `127.0.0.1`, `[::1]`)

**Test 1 - Evil host rejected:**
```
Host: evil.example.com
Origin: http://evil.example.com
```
Must return HTTP 4xx (400–499).

**Test 2 - Valid localhost accepted:**
```
Host: localhost:3000  (actual server host)
Origin: http://localhost:3000
```
Must return HTTP 2xx (200–299).

**Implementation:** Use `createMcpExpressApp()` from `@modelcontextprotocol/sdk/server/express.js` which provides built-in DNS rebinding protection. (`everything-server.ts:1185`)

---

## 10. Stateless Lifecycle (2026-07-28 draft spec, SEP-2575)

### 10.1 Overview

**Source:** `src/scenarios/server/stateless.ts`, `everything-server.ts:1228-2330`

The `2026-07-28` spec replaces the stateful `initialize`/session lifecycle with per-request `_meta` and `server/discover`.

### 10.2 Per-Request `_meta` Structure

Every request to a stateless server MUST carry:
```json
{
  "_meta": {
    "io.modelcontextprotocol/protocolVersion": "2026-07-28",
    "io.modelcontextprotocol/clientInfo": { "name": "...", "version": "..." },
    "io.modelcontextprotocol/clientCapabilities": {}
  }
}
```

`clientInfo` is a SHOULD (optional); `protocolVersion` and `clientCapabilities` are MUST.

**Header:** `MCP-Protocol-Version: 2026-07-28` must match `_meta.io.modelcontextprotocol/protocolVersion`.

### 10.3 Error Codes for Stateless Validation Failures

| Condition | HTTP | JSON-RPC code |
|-----------|------|---------------|
| Missing `MCP-Protocol-Version` header | 400 | `-32020` |
| Missing `_meta` or required `_meta` fields | 400 | `-32602` |
| Header/`_meta` version mismatch | 400 | `-32020` |
| Unsupported protocol version | 400 | `-32022` `UnsupportedProtocolVersionError` with `data.supported: ["2026-07-28"], data.requested: <version>` |
| Missing required client capability | 400 | `-32021` `MissingRequiredClientCapabilityError` with `data.requiredCapabilities: { "sampling": {} }` |
| Removed methods (initialize, ping, logging/setLevel, resources/subscribe, resources/unsubscribe) | 404 | `-32601` |
| Unknown method | 404 | `-32601` |

**Source:** `everything-server.ts:1287-1330`

### 10.4 `server/discover` Method

Stateless servers MUST implement `server/discover`:
```json
{
  "result": {
    "resultType": "complete",
    "supportedVersions": ["2026-07-28"],
    "capabilities": {
      "tools": { "listChanged": true },
      "prompts": { "listChanged": true },
      "resources": {}
    },
    "_meta": {
      "io.modelcontextprotocol/serverInfo": {
        "name": "everything-stateless-server",
        "version": "1.0.0"
      }
    },
    "ttlMs": 0,
    "cacheScope": "private"
  }
}
```
**Source:** `everything-server.ts:1392-1414`

### 10.5 Caching Hints (SEP-2549)

Cacheable stateless methods MUST include `ttlMs` and `cacheScope` in result:

| Method | `ttlMs` | `cacheScope` |
|--------|---------|--------------|
| `server/discover` | 0 | `"private"` |
| `tools/list` | 300000 | `"public"` |
| `prompts/list` | 300000 | `"public"` |
| `resources/list` | 300000 | `"public"` |
| `resources/templates/list` | 300000 | `"public"` |
| `resources/read` | 300000 | `"private"` |

**Source:** `everything-server.ts:1239-1265`

All stateless results also carry `resultType: "complete"` (stamped automatically).

### 10.6 `subscriptions/listen` Stream

Stateless servers MUST implement a long-lived chunked-transfer stream:
1. First frame MUST be `notifications/subscriptions/acknowledged` with `_meta.io.modelcontextprotocol/subscriptionId`
2. Subsequent frames deliver `notifications/tools/list_changed` or `notifications/prompts/list_changed` (matching client filter)
3. Frames are newline-delimited JSON (not SSE)

**Ack frame:**
```json
{
  "jsonrpc": "2.0",
  "method": "notifications/subscriptions/acknowledged",
  "params": {
    "_meta": { "io.modelcontextprotocol/subscriptionId": "<request-id-as-string>" },
    "notifications": { "toolsListChanged": true }
  }
}
```
**Source:** `everything-server.ts:1361-1389`

### 10.7 `tools/call` on Stateless Path

On the stateless path, `tools/call` is answered as `text/event-stream` (SSE):
```
Content-Type: text/event-stream
Transfer-Encoding: chunked

event: message
data: {"jsonrpc":"2.0","method":"notifications/progress",...}

event: message
data: {"jsonrpc":"2.0","id":1,"result":{...}}
```
**Source:** `everything-server.ts:2246-2272`

### 10.8 SDK Stateless Toggle

| SDK | Stateless enable |
|-----|-----------------|
| `go-sdk` | `-stateless=false` default; `2026-07-28` drops flag (defaults stateless) |
| `rust-sdk` | `STATELESS=1` env var |
| `csharp-sdk` | Different URL: `/stateless` endpoint |
| `python-sdk` | No toggle; same binary for both (2026-07-28 uses different baseline) |
| `typescript-sdk` | Handled in same server at POST `/mcp`; detects missing `MCP-Session-Id` + draft version |

**Source:** `src/sdk-runner/known-sdks.ts:46-154`

---

## 11. Magic Values Summary

| Constant | Value | Source |
|----------|-------|--------|
| `TEST_IMAGE_BASE64` | `iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg==` | `everything-server.ts:159-160` |
| `TEST_AUDIO_BASE64` | `UklGRiYAAABXQVZFZm10IBAAAAABAAEAQB8AAAB9AAACABAAZGF0YQIAAAA=` | `everything-server.ts:162-164` |
| Simple text response | `"This is a simple text response for testing."` | `everything-server.ts:310` |
| Static text resource content | `"This is the content of the static text resource."` | `everything-server.ts:869` |
| Watched resource content | `"Watched resource content"` | `everything-server.ts:43` |
| Embedded resource text | `"This is an embedded resource content."` | `everything-server.ts:360` |
| Embedded resource URI | `"test://embedded-resource"` | `everything-server.ts:358` |
| Mixed content resource URI | `"test://mixed-content-resource"` | `everything-server.ts:384` |
| Mixed content resource text | `'{"test":"data","value":123}'` (JSON stringified) | `everything-server.ts:385` |
| Simple prompt text | `"This is a simple prompt for testing."` | `everything-server.ts:987` |
| Prompt with args text | `"Prompt with arguments: arg1='${arg1}', arg2='${arg2}'"` | `everything-server.ts:1015` |
| Embedded resource prompt text | `"Embedded resource content for testing."` | `everything-server.ts:1043` |
| Progress tool: return text | `String(progressToken)` (the token echoed back) | `everything-server.ts:477` |
| Error tool message | `"This tool intentionally returns an error for testing"` | `everything-server.ts:489` |
| Reconnection tool response | `"Reconnection test completed successfully. ..."` | `everything-server.ts:523-528` |

---

## 12. Complete Tool Registry

| Tool Name | Arguments | Return Type | Scenario |
|-----------|-----------|-------------|----------|
| `test_simple_text` | none | text | `tools-call-simple-text` |
| `test_image_content` | none | image/png | `tools-call-image` |
| `test_audio_content` | none | audio/wav | `tools-call-audio` |
| `test_embedded_resource` | none | resource | `tools-call-embedded-resource` |
| `test_multiple_content_types` | none | text+image+resource | `tools-call-mixed-content` |
| `test_tool_with_logging` | none (empty schema) | text + 3 log notifications | `tools-call-with-logging` |
| `test_tool_with_progress` | none (empty schema) | text + 3 progress notifications | `tools-call-with-progress` |
| `test_error_handling` | none | isError:true + text | `tools-call-error` |
| `test_reconnection` | none (empty schema) | text (after SSE reconnect) | `server-sse-polling` |
| `test_sampling` | `prompt` (string) | text (after sampling) | `tools-call-sampling` |
| `test_elicitation` | `message` (string) | text (after elicitation) | `tools-call-elicitation` |
| `test_elicitation_sep1034_defaults` | none (empty schema) | text | `elicitation-sep1034-defaults` |
| `test_elicitation_sep1330_enums` | none (empty schema) | text | `elicitation-sep1330-enums` |
| `json_schema_2020_12_tool` | see schema above | text | `json-schema-2020-12` |

---

## 13. Complete Resource Registry

| Resource Name | URI | MIME | Content |
|---------------|-----|------|---------|
| `static-text` | `test://static-text` | `text/plain` | `"This is the content of the static text resource."` |
| `static-binary` | `test://static-binary` | `image/png` | TEST_IMAGE_BASE64 (blob) |
| `watched-resource` | `test://watched-resource` | `text/plain` | `"Watched resource content"` |
| Template | `test://template/{id}/data` | `application/json` | `{"id":"<id>","templateTest":true,"data":"Data for ID: <id>"}` |

---

## 14. Complete Prompt Registry

| Prompt Name | Arguments | Response Shape |
|-------------|-----------|----------------|
| `test_simple_prompt` | none | 1 message: user/text |
| `test_prompt_with_arguments` | `arg1`, `arg2` (strings) | 1 message: user/text with args interpolated |
| `test_prompt_with_embedded_resource` | `resourceUri` (string) | 2 messages: user/resource, user/text |
| `test_prompt_with_image` | none | 2 messages: user/image, user/text |

---

## 15. Transport Requirements

### Stateful (2025-06-18 / 2025-11-25)

**Endpoint:** `POST /mcp`

**Session lifecycle:**
1. `POST /mcp` → `initialize` → responds with `MCP-Session-Id` header (visible ASCII only)
2. `POST /mcp` + `MCP-Session-Id` → `notifications/initialized` → `{}` (2xx)
3. Subsequent requests carry `MCP-Session-Id` + `MCP-Protocol-Version` headers
4. `GET /mcp` + `MCP-Session-Id` → SSE stream for server-push
5. `DELETE /mcp` + `MCP-Session-Id` → terminates session (returns 2xx or 405)
6. After DELETE: requests with that session ID must return HTTP 404

**Unknown session ID:** HTTP 404 `{"code": -32001, "message": "Session not found"}`

**No session on non-initialize request:** HTTP 400 `{"code": -32000, "message": "Invalid or missing session ID"}`

**SSE stream format (GET):** `text/event-stream`, standard SSE with `event:`, `data:`, `id:`, `retry:` fields.

**SSE stream format (POST response):** `text/event-stream` or `application/json`

### Stateless (2026-07-28)

**Endpoint:** `POST /mcp` (same endpoint, distinguished by absence of `MCP-Session-Id`)

**Per-request headers:**
```
MCP-Protocol-Version: 2026-07-28
Content-Type: application/json
Accept: application/json, text/event-stream
```

**Response:** JSON or SSE depending on method (tools/call → SSE; others → JSON)

**CORS:** Expose `Mcp-Session-Id` header, allow `Content-Type`, `mcp-session-id`, `last-event-id` headers.

---

## 16. Scenario Version Gating

| Scenario | Introduced | Removed In |
|----------|-----------|-----------|
| `server-initialize` | `2025-06-18` | `2026-07-28` |
| `logging-set-level` | `2025-06-18` | `2026-07-28` |
| `ping` | `2025-06-18` | `2026-07-28` |
| `tools-call-simple-text` | `2025-06-18` | — |
| `tools-call-image` | `2025-06-18` | — |
| `tools-call-audio` | `2025-06-18` | — |
| `tools-call-embedded-resource` | `2025-06-18` | — |
| `tools-call-mixed-content` | `2025-06-18` | — |
| `tools-call-with-logging` | `2025-06-18` | `2026-07-28` |
| `tools-call-error` | `2025-06-18` | — |
| `tools-call-with-progress` | `2025-06-18` | — |
| `tools-call-sampling` | `2025-06-18` | `2026-07-28` |
| `tools-call-elicitation` | `2025-06-18` | `2026-07-28` |
| `json-schema-2020-12` | `2025-11-25` | — |
| `elicitation-sep1034-defaults` | `2025-11-25` | `2026-07-28` |
| `elicitation-sep1330-enums` | `2025-11-25` | `2026-07-28` |
| `server-sse-polling` | `2025-11-25` | `2026-07-28` |
| `server-sse-multiple-streams` | `2025-11-25` | — |
| `resources-list` | `2025-06-18` | — |
| `resources-read-text` | `2025-06-18` | — |
| `resources-read-binary` | `2025-06-18` | — |
| `resources-templates-read` | `2025-06-18` | — |
| `resources-subscribe` | `2025-06-18` | `2026-07-28` |
| `resources-unsubscribe` | `2025-06-18` | `2026-07-28` |
| `prompts-list` | `2025-06-18` | — |
| `prompts-get-simple` | `2025-06-18` | — |
| `prompts-get-with-args` | `2025-06-18` | — |
| `prompts-get-embedded-resource` | `2025-06-18` | — |
| `prompts-get-with-image` | `2025-06-18` | — |
| `completion-complete` | `2025-06-18` | — |
| `dns-rebinding-protection` | `2025-11-25` | — |

**DRAFT_PROTOCOL_VERSION constant = `"2026-07-28"`** (`src/types.ts:50`)

---

## Summary of Biggest Implementation Requirements

Here are the critical implementation requirements for the R SDK everything-server:

1. **14 tools must be registered** with exact names, exact return values including magic strings and base64 blobs. The `test_audio_content` tool's `mimeType` is checked to be exactly `"audio/wav"`. The `test_tool_with_progress` must echo back the progressToken as its text content.

2. **Tool error semantics**: `test_error_handling` must throw an exception (SDK converts to `isError: true` in result, NOT a JSON-RPC error response). The check is `result.isError === true`.

3. **JSON Schema 2020-12 fidelity**: `json_schema_2020_12_tool` must return the exact raw schema (with `$schema`, `$defs`, `additionalProperties`, `allOf`, `if/then/else`) — the SDK must NOT strip these fields during `tools/list`.

4. **4 resources + 1 template**: with exact URIs and exact text/blob content values. The template must perform `{id}` substitution and the content must contain the substituted value (checked by string inclusion).

5. **Elicitation schemas must be byte-exact**: The `sep1034-defaults` schema requires exact `default` values per field type. The `sep1330-enums` schema requires 5 specific enum variants using different structures (plain `enum`, `oneOf`, `enumNames`, `items.enum`, `items.anyOf`).

6. **SSE polling/reconnection**: Requires an in-memory event store, `retryInterval: 5000`, and the `test_reconnection` tool that actively closes the SSE stream mid-call.

7. **DNS rebinding**: Must use a framework that validates `Host`/`Origin` headers on localhost, rejecting non-localhost origins with 4xx.

8. **Stateless (2026-07-28) is a completely different path**: No `initialize`, per-request `_meta`, `server/discover`, `subscriptions/listen` stream, caching hints on all list/read results, `tools/call` as SSE, and removed-method returns `404 + -32601`.

9. **Session lifecycle**: `DELETE /mcp` with `MCP-Session-Id` must be handled; subsequent requests with that session ID must return `404`.

10. **Logging**: 3 `notifications/message` events at `info` level during `test_tool_with_logging` execution, with `data` fields containing exact strings.

---
