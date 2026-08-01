header_echo_tool <- ellmer::tool(
  fun = function(value) value,
  name = "test_header_echo",
  description = "Echoes a value supplied through an MCP parameter header",
  arguments = list(
    value = ellmer::type_string("The value to echo")
  )
)
attr(header_echo_tool, "mcp_input_schema") <- list(
  type = "object",
  properties = list(
    value = list(
      type = "string",
      `x-mcp-header` = "value"
    )
  ),
  required = list("value")
)

mrtr_tools <- lapply(
  c(
    "test_input_required_result_elicitation",
    "test_input_required_result_sampling",
    "test_input_required_result_list_roots",
    "test_input_required_result_request_state",
    "test_input_required_result_multiple_inputs",
    "test_input_required_result_multi_round",
    "test_input_required_result_tampered_state",
    "test_input_required_result_capabilities"
  ),
  function(name) {
    ellmer::tool(
      fun = function() "Input-required workflow completed",
      name = name,
      description = "Exercises a stateless multi-round-trip request"
    )
  }
)

c(list(
  ellmer::tool(
    fun = function() "Capability requirement satisfied",
    name = "test_missing_capability",
    description = "Requires the client sampling capability"
  ),
  ellmer::tool(
    fun = function() "Streaming elicitation completed",
    name = "test_streaming_elicitation",
    description = "Exercises a stateless response stream"
  ),
  ellmer::tool(
    fun = function() "Logging tool completed",
    name = "test_logging_tool",
    description = "Only logs when explicitly requested"
  ),
  ellmer::tool(
    fun = function() "Tool list changed",
    name = "test_trigger_tool_change",
    description = "Triggers a tools list-changed notification"
  ),
  ellmer::tool(
    fun = function() "Prompt list changed",
    name = "test_trigger_prompt_change",
    description = "Triggers a prompts list-changed notification"
  ),
  header_echo_tool
), mrtr_tools)
