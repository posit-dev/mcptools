mcp_elicitation_request <- function(data, id) {
  tool_name <- data$params$name
  params <- switch(
    tool_name,
    test_elicitation = list(
      message = data$params$arguments$message,
      requestedSchema = list(
        type = "object",
        properties = list(
          response = list(
            type = "string",
            description = "User's response"
          )
        ),
        required = list("response")
      )
    ),
    test_elicitation_sep1034_defaults = list(
      message = "Please review and update the form fields with defaults",
      requestedSchema = elicitation_defaults_schema()
    ),
    test_elicitation_sep1330_enums = list(
      message = "Please select values for each enum field",
      requestedSchema = elicitation_enums_schema()
    )
  )

  list(
    jsonrpc = "2.0",
    id = id,
    method = "elicitation/create",
    params = params
  )
}

mcp_elicitation_tool_response <- function(
  response,
  tool_request_id,
  tool_name
) {
  if (!is.null(response$error)) {
    return(mcp_server_request_tool_error(
      tool_request_id,
      response$error$message %||% "Elicitation request failed"
    ))
  }

  result <- response$result
  prefix <- if (identical(tool_name, "test_elicitation")) {
    "User response"
  } else {
    "Elicitation completed"
  }
  content <- if (is.null(result$content)) {
    "{}"
  } else {
    as.character(to_json(result$content))
  }

  jsonrpc_response(
    tool_request_id,
    result = list(content = list(list(
      type = "text",
      text = sprintf(
        "%s: action=%s, content=%s",
        prefix,
        result$action %||% "cancel",
        content
      )
    )))
  )
}

elicitation_defaults_schema <- function() {
  list(
    type = "object",
    properties = list(
      name = list(
        type = "string",
        description = "User name",
        default = "John Doe"
      ),
      age = list(
        type = "integer",
        description = "User age",
        default = 30L
      ),
      score = list(
        type = "number",
        description = "User score",
        default = 95.5
      ),
      status = list(
        type = "string",
        description = "User status",
        enum = c("active", "inactive", "pending"),
        default = "active"
      ),
      verified = list(
        type = "boolean",
        description = "Verification status",
        default = TRUE
      )
    ),
    required = list()
  )
}

elicitation_enums_schema <- function() {
  list(
    type = "object",
    properties = list(
      untitledSingle = list(
        type = "string",
        description = "Select one option",
        enum = c("option1", "option2", "option3")
      ),
      titledSingle = list(
        type = "string",
        description = "Select one option with titles",
        oneOf = list(
          list(const = "value1", title = "First Option"),
          list(const = "value2", title = "Second Option"),
          list(const = "value3", title = "Third Option")
        )
      ),
      legacyEnum = list(
        type = "string",
        description = "Select one option (legacy)",
        enum = c("opt1", "opt2", "opt3"),
        enumNames = c("Option One", "Option Two", "Option Three")
      ),
      untitledMulti = list(
        type = "array",
        description = "Select multiple options",
        minItems = 1L,
        maxItems = 3L,
        items = list(
          type = "string",
          enum = c("option1", "option2", "option3")
        )
      ),
      titledMulti = list(
        type = "array",
        description = "Select multiple options with titles",
        minItems = 1L,
        maxItems = 3L,
        items = list(anyOf = list(
          list(const = "value1", title = "First Choice"),
          list(const = "value2", title = "Second Choice"),
          list(const = "value3", title = "Third Choice")
        ))
      )
    ),
    required = list()
  )
}

mcp_server_request_tool_error <- function(id, message) {
  jsonrpc_response(
    id,
    result = list(
      content = list(list(type = "text", text = message)),
      isError = TRUE
    )
  )
}
