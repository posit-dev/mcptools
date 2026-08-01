.mcp_completion_complete <- function(data, protocol_version, transport) {
  list(completion = list(
    values = list(),
    total = 0L,
    hasMore = FALSE
  ))
}

.register_mcp_completion <- function() {
  register_mcp_method("completion/complete", .mcp_completion_complete)
  register_mcp_capability(list(completions = named_list()))
}
