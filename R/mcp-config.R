#' Generate Model Context Protocol (MCP) configuration
#'
#' @description
#' This function provides instructions to configure acquaint with LLM-enabled
#' tools like Claude Code or Claude Desktop.
#' 
#' @param which The name of the application to configure with acquaint. Currently,
#' one of "Claude Code" or "Claude Desktop".
#' 
#' @returns 
#' A character vector containing the MCP configuration 
#' instructions, invisibly. The function also prints the configuration to 
#' the console.
#' 
#' @examples
#' mcp_config("Claude Code")
#' 
#' # Claude Desktop currently isn't available on Linux
#' if (!identical(tolower(Sys.info()[["sysname"]]), "linux")) {
#'   mcp_config("Claude Desktop")
#' }
#' 
# quiet R CMD check note about unused import
#' @importFrom btw btw
#' @export
mcp_config <- function(which = c("Claude Code", "Claude Desktop")) {
  which <- match.arg(which, choices = c("Claude Code", "Claude Desktop"))

  res <-
    switch(
      which,
      `Claude Code` = mcp_config_claude_code(),
      `Claude Desktop` = mcp_config_claude_desktop()
    )
  
  cat(res, sep = "\n")

  invisible(res)
}

mcp_config_claude_code <- function() {
  c(
    'In a terminal, run:',
    '',
    paste0(
      'claude mcp add -s "user" r-acquaint node ',
      system.file("node/dist/index.js", package = "acquaint")
    )
  )
}

mcp_config_claude_desktop <- function() {
  if (is_linux()) {
    stop("Claude Desktop isn't available on Linux.")
  }

  config_path <- if (is_windows()) {
    "%APPDATA%\\Claude\\claude_desktop_config.json"
  } else {
    "~/Library/Application Support/Claude/claude_desktop_config.json"
  }

  c(
    # TODO: make this path system-dependent
    paste0('Run `file.edit("', config_path, '")`'),
    '',
    'Then, paste the following:',
    '{',
    '  "mcpServers": {',
    '    "r-acquaint": {',
    '      "command": "node",',
    paste0(
      '      "args": ["',
      system.file("node/dist/index.js", package = "acquaint"),
      '"]'
    ),
    '    }',
    '  }',
    '}'
  )
}

is_linux <- function() {
  identical(tolower(Sys.info()[["sysname"]]), "linux")
}

is_windows <- function() {
  identical(.Platform$OS.type, "windows")
}

system.file <- NULL
