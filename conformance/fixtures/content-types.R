TEST_IMAGE_BASE64 <- paste0(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ",
  "AAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
)
TEST_AUDIO_BASE64 <- paste0(
  "UklGRiYAAABXQVZFZm10IBAAAAABAAEAQB8AAAB9AAAC",
  "ABAAZGF0YQIAAAA="
)

json_schema_2020_12_tool <- ellmer::tool(
  fun = function() "JSON Schema 2020-12 tool executed successfully.",
  name = "json_schema_2020_12_tool",
  description = "Tests preservation of JSON Schema draft 2020-12"
)
attr(json_schema_2020_12_tool, "mcp_input_schema") <- list(
  `$schema` = "https://json-schema.org/draft/2020-12/schema",
  type = "object",
  `$defs` = list(
    address = list(
      `$anchor` = "addressDef",
      type = "object",
      properties = list(
        street = list(type = "string"),
        city = list(type = "string")
      )
    )
  ),
  properties = list(
    name = list(type = "string"),
    address = list(`$ref` = "#/$defs/address"),
    contactMethod = list(type = "string", enum = c("phone", "email")),
    phone = list(type = "string"),
    email = list(type = "string")
  ),
  allOf = list(
    list(
      anyOf = list(
        list(required = list("phone")),
        list(required = list("email"))
      )
    )
  ),
  `if` = list(
    properties = list(contactMethod = list(const = "phone")),
    required = list("contactMethod")
  ),
  then = list(required = list("phone")),
  `else` = list(required = list("email")),
  additionalProperties = FALSE
)

list(
  ellmer::tool(
    fun = function() "This is a simple text response for testing.",
    name = "test_simple_text",
    description = "Tests simple text content response"
  ),
  ellmer::tool(
    fun = function() {
      ellmer::ContentImageInline(
        type = "image/png",
        data = TEST_IMAGE_BASE64
      )
    },
    name = "test_image_content",
    description = "Tests image content response"
  ),
  ellmer::tool(
    fun = function() {
      list(
        type = "audio",
        data = TEST_AUDIO_BASE64,
        mimeType = "audio/wav"
      )
    },
    name = "test_audio_content",
    description = "Tests audio content response"
  ),
  ellmer::tool(
    fun = function() {
      list(
        type = "resource",
        resource = list(
          uri = "test://embedded-resource",
          mimeType = "text/plain",
          text = "This is an embedded resource content."
        )
      )
    },
    name = "test_embedded_resource",
    description = "Tests embedded resource content response"
  ),
  ellmer::tool(
    fun = function() {
      list(
        list(type = "text", text = "Multiple content types test:"),
        list(
          type = "image",
          data = TEST_IMAGE_BASE64,
          mimeType = "image/png"
        ),
        list(
          type = "resource",
          resource = list(
            uri = "test://mixed-content-resource",
            mimeType = "application/json",
            text = "{\"test\":\"data\",\"value\":123}"
          )
        )
      )
    },
    name = "test_multiple_content_types",
    description = "Tests mixed content response"
  ),
  ellmer::tool(
    fun = function() {
      stop(
        "This tool intentionally returns an error for testing",
        call. = FALSE
      )
    },
    name = "test_error_handling",
    description = "Tests tool execution error response"
  ),
  json_schema_2020_12_tool
)
