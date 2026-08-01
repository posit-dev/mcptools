.register_mcp_core <- function() {
  register_mcp_method(
    "ping",
    function(data, protocol_version, transport) named_list()
  )
}
