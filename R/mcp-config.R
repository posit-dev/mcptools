#' Generate model context protocol configuration
#'
#' @description
#' This function provides the `.json` needed to configure rmcp with LLM-enabled
#' tools like Claude Code or Claude for Desktop.
#' 
#' @returns 
#' A character vector containing the MCP configuration JSON, invisibly. The 
#' function also prints the configuration to the console.
#' 
#' @examples
#' mcp_config()
#' 
#' @export
mcp_config <- function() {
  res <-
    c(
      '{',
      '  "mcpServers": {',
      '    "r-mcp": {',
      '      "command": "node",',
      paste0(
        '      "args": ["',
        system.file("node/dist/index.js", package = "rmcp"),
        '"]'
      ),
      '    }',
      '  }',
      '}'
    )
  
  cat(res, sep = "\n")

  invisible(res)
}
