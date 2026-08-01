the <- new_environment()
the$server_processes <- list()
the$http_allowed_origins <- character()
the$http_trusted_hosts <- character()
the$http_shared_secret <- NULL
the$socket_secret <- NULL
the$mrtr_state_secret <- NULL
# MCP extension registry (see R/mcp-registry.R)
the$mcp_methods <- list()
the$mcp_capabilities <- list()
