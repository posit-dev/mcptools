.mcp_logging_set_level <- function(data, protocol_version, transport) {
  named_list()
}

.register_mcp_logging <- function() {
  register_mcp_method("logging/setLevel", .mcp_logging_set_level)
  register_mcp_capability(list(logging = named_list()))
}
