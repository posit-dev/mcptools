.mcp_resources_list <- function(data, protocol_version, transport) {
  list(resources = list(
    list(
      uri = "test://static-text",
      name = "static-text",
      mimeType = "text/plain"
    ),
    list(
      uri = "test://static-binary",
      name = "static-binary",
      mimeType = "image/png"
    ),
    list(
      uri = "test://watched-resource",
      name = "watched-resource",
      mimeType = "text/plain"
    )
  ))
}

.mcp_resources_read <- function(data, protocol_version, transport) {
  uri <- data$params$uri

  if (identical(uri, "test://static-text")) {
    return(list(contents = list(
      list(
        uri = uri,
        mimeType = "text/plain",
        text = "This is the content of the static text resource."
      )
    )))
  }

  if (identical(uri, "test://static-binary")) {
    return(list(contents = list(
      list(
        uri = uri,
        mimeType = "image/png",
        blob = paste0(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlE",
          "QVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
        )
      )
    )))
  }

  if (identical(uri, "test://watched-resource")) {
    return(list(contents = list(
      list(
        uri = uri,
        mimeType = "text/plain",
        text = "Watched resource content"
      )
    )))
  }

  if (is_string(uri) && grepl("^test://template/([^/]+)/data$", uri)) {
    id <- sub("^test://template/([^/]+)/data$", "\\1", uri)
    text <- jsonlite::toJSON(
      list(
        id = id,
        templateTest = TRUE,
        data = paste0("Data for ID: ", id)
      ),
      auto_unbox = TRUE
    )

    return(list(contents = list(
      list(
        uri = uri,
        mimeType = "application/json",
        text = as.character(text)
      )
    )))
  }

  uri_label <- if (is_string(uri)) uri else "<missing>"
  jsonrpc_error(-32602, paste("Resource not found:", uri_label))
}

.mcp_resources_templates_list <- function(data, protocol_version, transport) {
  list(resourceTemplates = list(
    list(
      uriTemplate = "test://template/{id}/data",
      name = "template",
      mimeType = "application/json"
    )
  ))
}

.mcp_resources_subscribe <- function(data, protocol_version, transport) {
  named_list()
}

.mcp_resources_unsubscribe <- function(data, protocol_version, transport) {
  named_list()
}

.register_mcp_resources <- function() {
  register_mcp_method("resources/list", .mcp_resources_list)
  register_mcp_method("resources/read", .mcp_resources_read)
  register_mcp_method(
    "resources/templates/list",
    .mcp_resources_templates_list
  )
  register_mcp_method("resources/subscribe", .mcp_resources_subscribe)
  register_mcp_method("resources/unsubscribe", .mcp_resources_unsubscribe)
  register_mcp_capability(list(
    resources = named_list(subscribe = TRUE, listChanged = FALSE)
  ))
}
