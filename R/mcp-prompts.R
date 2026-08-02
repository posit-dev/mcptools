.mcp_prompts_list <- function(data, protocol_version, transport) {
  list(prompts = list(
    list(
      name = "test_simple_prompt",
      description = "A simple prompt"
    ),
    list(
      name = "test_prompt_with_arguments",
      description = "A prompt with arguments",
      arguments = list(
        list(
          name = "arg1",
          description = "First argument",
          required = FALSE
        ),
        list(
          name = "arg2",
          description = "Second argument",
          required = FALSE
        )
      )
    ),
    list(
      name = "test_prompt_with_embedded_resource",
      description = "A prompt with an embedded resource",
      arguments = list(list(
        name = "resourceUri",
        description = "Resource URI",
        required = FALSE
      ))
    ),
    list(
      name = "test_prompt_with_image",
      description = "A prompt with an image"
    )
  ))
}

.mcp_prompts_get <- function(data, protocol_version, transport) {
  name <- data$params$name

  if (identical(name, "test_simple_prompt")) {
    return(list(messages = list(list(
      role = "user",
      content = list(
        type = "text",
        text = "This is a simple prompt for testing."
      )
    ))))
  }

  if (identical(name, "test_prompt_with_arguments")) {
    arguments <- data$params$arguments
    text <- sprintf(
      "Prompt with arguments: arg1='%s', arg2='%s'",
      arguments$arg1,
      arguments$arg2
    )
    return(list(messages = list(list(
      role = "user",
      content = list(type = "text", text = text)
    ))))
  }

  if (identical(name, "test_prompt_with_embedded_resource")) {
    resource_uri <- data$params$arguments$resourceUri
    return(list(messages = list(
      list(
        role = "user",
        content = list(
          type = "resource",
          resource = list(
            uri = resource_uri,
            mimeType = "text/plain",
            text = "Embedded resource content for testing."
          )
        )
      ),
      list(
        role = "user",
        content = list(
          type = "text",
          text = "Please process the embedded resource above."
        )
      )
    )))
  }

  if (identical(name, "test_prompt_with_image")) {
    return(list(messages = list(
      list(
        role = "user",
        content = list(
          type = "image",
          data = paste0(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlE",
            "QVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
          ),
          mimeType = "image/png"
        )
      ),
      list(
        role = "user",
        content = list(
          type = "text",
          text = "Please analyze the image above."
        )
      )
    )))
  }

  jsonrpc_error(-32602, paste("Unknown prompt:", name))
}

.register_mcp_prompts <- function() {
  register_mcp_method("prompts/list", .mcp_prompts_list)
  register_mcp_method("prompts/get", .mcp_prompts_get)
  register_mcp_capability(list(
    prompts = named_list(listChanged = FALSE)
  ))
}
