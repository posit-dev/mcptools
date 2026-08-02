list(
  ellmer::tool(
    fun = function() "Tool with logging executed successfully",
    name = "test_tool_with_logging",
    description = "Emits logging notifications while executing"
  ),
  ellmer::tool(
    fun = function() "Progress token is supplied through MCP request metadata",
    name = "test_tool_with_progress",
    description = "Emits progress notifications while executing"
  ),
  ellmer::tool(
    fun = function() {
      paste(
        "Reconnection test completed successfully.",
        "The SSE stream remained available."
      )
    },
    name = "test_reconnection",
    description = "Tests SSE reconnection behavior"
  ),
  ellmer::tool(
    fun = function(prompt) paste0("LLM response: ", prompt),
    name = "test_sampling",
    description = "Requests LLM sampling from the client",
    arguments = list(
      prompt = ellmer::type_string("The prompt to send to the LLM")
    )
  ),
  ellmer::tool(
    fun = function(message) paste0("User response: ", message),
    name = "test_elicitation",
    description = "Requests structured user input from the client",
    arguments = list(
      message = ellmer::type_string("The message to show the user")
    )
  ),
  ellmer::tool(
    fun = function() "Elicitation completed with default values",
    name = "test_elicitation_sep1034_defaults",
    description = "Tests elicitation default values"
  ),
  ellmer::tool(
    fun = function() "Elicitation completed with enum values",
    name = "test_elicitation_sep1330_enums",
    description = "Tests elicitation enum schema variants"
  )
)
