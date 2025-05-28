# This file implements R as the _client_.

# tools ------------------------------------------------------------------------
# each named entry is:
# name: the name of the server (from the config)
# process: the processx process object
# tools: a named list of tools
# id: the current jsonrpc message id
the$mcp_servers <- list()

#' Collect ellmer chats with tools from MCP servers
#'
#' @description
#' `mcp_tools()` fetches tools from MCP servers configured in the acquaint
#' server config file at `set_mcp_config()` and converts them to a list of
#' tools compatible with the `$set_tools()` method of [ellmer::Chat] objects.
#'
#' @section Configuration:
#'
#' acquaint uses the same .json configuration file format as Claude Desktop.
#' By default, the package will look to
#' `file.path("~", ".config", "acquaint", "config.json")`; you can edit that
#' file with `file.edit(file.path("~", ".config", "acquaint", "config.json"))`,
#' or you can supply an alternative file path with `set_mcp_config()`.
#'
#' For example, to configure `mcp_tools()` with GitHub's official MCP Server
#' <https://github.com/github/github-mcp-server>, I could write the following
#' in that file:
#'
#' ```json
#' {
#'   "mcpServers": {
#'     "github": {
#'       "command": "docker",
#'       "args": [
#'         "run",
#'         "-i",
#'         "--rm",
#'         "-e",
#'         "GITHUB_PERSONAL_ACCESS_TOKEN",
#'         "ghcr.io/github/github-mcp-server"
#'       ],
#'       "env": {
#'         "GITHUB_PERSONAL_ACCESS_TOKEN": "<add_your_github_pat_here>"
#'       }
#'     }
#'   }
#' }
#' ```
#'
#'
#' @name client
#' @export
mcp_tools <- function() {
  config_file <- get_mcp_config()
  config <- jsonlite::fromJSON(readLines(config_file))$mcpServers

  for (i in seq_along(config)) {
    config_i <- config[[i]]
    name_i <- names(config)[i]

    process <- processx::process$new(
      # seems like the R process has a different PATH than process_exec
      command = Sys.which(config_i$command),
      args = config_i$args,
      env = unlist(config_i$env),
      stdin = "|",
      stdout = "|",
      stderr = "|"
    )

    add_mcp_server(process = process, name = name_i)
  }

  servers_as_ellmer_tools()
}

#' @param file A single string indicating the path to the acquaint MCP servers
#' configuration file. If one is not configured, acquaint will look for one in
#' `file.path("~", ".config", "acquaint", "config.json")`.
#'
#' @rdname client
#' @export
set_mcp_config <- function(file) {
  if (file.exists(file)) {
    cli::cli_abort("{.arg file} must exist.")
  }
  options(.acquaint_config = file)
  invisible(file)
}

get_mcp_config <- function() {
  getOption(
    ".acquaint_config",
    default = file.path("~", ".config", "acquaint", "config.json")
  )
}

add_mcp_server <- function(process, name) {
  response_initialize <- send_and_receive(process, mcp_request_initialize())
  response_tools_list <- send_and_receive(process, mcp_request_tools_list())

  the$mcp_servers[[name]] <- list(
    name = name,
    process = process,
    tools = response_tools_list$result,
    id = 3
  )

  the$mcp_servers[[name]]
}

servers_as_ellmer_tools <- function() {
  unname(unlist(
    lapply(the$mcp_servers, server_as_ellmer_tools),
    recursive = FALSE
  ))
}

server_as_ellmer_tools <- function(server) {
  tools_tbl <- server$tools$tools

  tools_out <- list()
  for (i in seq_len(nrow(tools_tbl))) {
    tool_description <- tools_tbl[[i, "description"]]
    tool_name <- tools_tbl[[i, "name"]]
    tool_arguments <- as_tool_arguments(tools_tbl[i, ]$inputSchema$properties)
    tools_out[[i]] <-
      do.call(
        ellmer::tool,
        c(
          list(
            .fun = tool_ref(
              server = server$name,
              tool = tool_name,
              arguments = names(tool_arguments)
            ),
            .description = tool_description,
            .name = tool_name
          ),
          tool_arguments
        )
      )
  }

  tools_out
}

as_tool_arguments <- function(x) {
  arguments <- as.list(x)
  compact(lapply(arguments, as_tool_argument))
}

as_tool_argument <- function(arg) {
  if (is.na(arg$type)) {
    return(NULL)
  }
  # TODO: we can probably just assemble a call2 here?
  switch(
    arg$type,
    string = ellmer::type_string(arg$description),
    number = ellmer::type_number(arg$description),
    integer = ellmer::type_integer(arg$description)
  )
}

# the output of this function is the function that the ellmer tool will
# reference. it will just invoke the right tool from `the$mcp_servers`.
tool_ref <- function(server, tool, arguments) {
  args_list <- setNames(vector("list", length = length(arguments)), arguments)

  # the actual formals of the function need to match the argument
  # descriptions in the tool object, so call the generic tool wrapper
  # (which can accept ...) via a wrapper with the proper formals.
  #
  # we get the formals via the function environment, so enclose it in a
  # tool-specific env via `crate()`.
  carrier::crate(
    {
      res <- function() {
        args <- mget(arguments, envir = environment())
        do.call(
          call_tool,
          c(
            compact(args),
            list(
              server = server,
              tool = tool
            )
          )
        )
      }
      formals(res) <- args_list
      res
    },
    server = server,
    tool = tool,
    arguments = arguments,
    compact = compact,
    call_tool = call_tool
  )
}

call_tool <- function(..., server, tool) {
  server_process <- the$mcp_servers[[server]]$process
  send_and_receive(
    server_process,
    mcp_request_tool_call(
      id = jsonrpc_id(server),
      tool = tool,
      arguments = list(...)
    )
  )
}

# retrieve and increment the current rsonrpc id from a server
jsonrpc_id <- function(server_name) {
  current_id <- the$mcp_servers[[server_name]]$id
  the$mcp_servers[[server_name]]$id <- current_id + 1
  current_id
}

# client protocol --------------------------------------------------------------
## stdio
log_cat_client <- function(x, append = TRUE) {
  log_file <- "~/mcp_client_test.txt"
  cat(x, "\n\n", sep = "", append = append, file = log_file)
}

send_and_receive <- function(process, message) {
  # send the message
  json_msg <- jsonlite::toJSON(message, auto_unbox = TRUE)
  log_cat_client(c("FROM CLIENT: ", json_msg))
  process$write_input(paste0(json_msg, "\n"))

  # poll for response
  output <- NULL
  attempts <- 0
  max_attempts <- 20

  while (length(output) == 0 && attempts < max_attempts) {
    Sys.sleep(0.2)
    output <- process$read_output_lines()
    attempts <- attempts + 1
  }

  if (!is.null(output) && length(output) > 0) {
    log_cat_client(c("FROM SERVER: ", output[1]))
    return(jsonlite::fromJSON(output[1]))
  }

  log_cat_client(c("ALERT: No response received after ", attempts, " attempts"))
  return(NULL)
}

# step 1: initialize the MCP connection
mcp_request_initialize <- function() {
  list(
    jsonrpc = "2.0",
    id = 1,
    method = "initialize",
    params = list(
      protocolVersion = "2024-11-05",
      capabilities = list(
        tools = list(
          listChanged = FALSE
        )
      ),
      clientInfo = list(
        name = "MCP Test Client",
        version = "0.1.0"
      )
    )
  )
}

# step 2: send initialized notification
# For some reason, if I send this, the buffer gets tied up and the following
# tools/list isn't appropriately responded to.
# Don't expect a response here, so no `receive()`
# initialized_notification <- list(
#   jsonrpc = "2.0",
#   method = "notifications/initialized"
# )
#
# r_process$write_input(jsonlite::toJSON(initialized_notification, auto_unbox = TRUE))

# step 3: request the list of tools
mcp_request_tools_list <- function() {
  list(
    jsonrpc = "2.0",
    id = 2,
    method = "tools/list"
  )
}

# step 4: call tools
mcp_request_tool_call <- function(id, tool, arguments) {
  if (length(arguments) == 0) {
    params <- list(name = tool)
  } else {
    params <- list(
      name = tool,
      arguments = arguments
    )
  }
  list(
    jsonrpc = "2.0",
    id = id,
    method = "tools/call",
    params = params
  )
}
