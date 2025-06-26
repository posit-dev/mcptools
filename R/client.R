# This file implements R as the _client_.

# tools ------------------------------------------------------------------------
# each named entry is:
# name: the name of the server (from the config)
# process: the processx process object
# tools: a named list of tools
# id: the current jsonrpc message id
the$mcp_servers <- list()

#' Define ellmer tools from MCP servers
#'
#' @description
#' These functions implement R as an MCP _client_, so that ellmer chats can
#' register functionality from third-party MCP servers such as those listed
#' here: <https://github.com/modelcontextprotocol/servers>.
#'
#' `mcp_tools()` fetches tools from MCP servers configured in the acquaint
#' server config file and converts them to a list of
#' tools compatible with the `$set_tools()` method of [ellmer::Chat] objects.
#'
#' @param path A single string indicating the path to the acquaint MCP servers
#' configuration file. If one is not supplied, acquaint will look for one at
#' the file path configured with the option `.acquaint_config`, falling back to
#' `file.path("~", ".config", "acquaint", "config.json")`.
#'
#' @section Configuration:
#'
#' acquaint uses the same .json configuration file format as Claude Desktop;
#' most MCP servers will define example .json to configure the server with
#' Claude Desktop in their README files. By default, acquaint will look to
#' `file.path("~", ".config", "acquaint", "config.json")`; you can edit that
#' file with `file.edit(file.path("~", ".config", "acquaint", "config.json"))`.
#'
#' The acquaint config file should be valid .json with an entry `mcpServers`.
#' That entry should contain named elements, each with at least a `command`
#' and `args` entry.
#'
#' For example, to configure `mcp_tools()` with GitHub's official MCP Server
#' <https://github.com/github/github-mcp-server>, you could write the following
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
#' @returns
#' * `mcp_tools()` returns a list of ellmer tools that can be passed directly
#' to the `$set_tools()` method of an [ellmer::Chat] object. If the file at
#' `path` doesn't exist, an error.
#'
#' @name client
#' @export
mcp_tools <- function(path = NULL) {
  if (is.null(path)) {
    path <- mcp_client_config()
  }

  config <- read_mcp_config(path)
  if (length(config) == 0) {
    return(list())
  }

  for (i in seq_along(config)) {
    config_i <- config[[i]]
    name_i <- names(config)[i]
    config_i_env <- if ("env" %in% names(config_i)) {
      unlist(config_i$env)
    } else {
      NULL
    }

    process <- processx::process$new(
      # seems like the R process has a different PATH than process_exec
      command = Sys.which(config_i$command),
      args = config_i$args,
      env = config_i_env,
      stdin = "|",
      stdout = "|",
      stderr = "|"
    )

    add_mcp_server(process = process, name = name_i)
  }

  servers_as_ellmer_tools()
}

mcp_client_config <- function() {
  getOption(
    ".acquaint_config",
    default = default_mcp_client_config()
  )
}

default_mcp_client_config <- function() {
  file.path("~", ".config", "acquaint", "config.json")
}

read_mcp_config <- function(path, call = caller_env()) {
  if (!file.exists(path)) {
    error_no_mcp_config(call = call)
  }

  config_lines <- readLines(path)
  if (length(config_lines) == 0) {
    return(list())
  }

  tryCatch(
    {
      config <- jsonlite::fromJSON(config_lines)
    },
    error = function(e) {
      cli::cli_abort(
        c(
          "Configuration processing failed",
          i = "The configuration file {.arg path} must be valid JSON."
        ),
        call = call,
        parent = e
      )
    }
  )

  if (!"mcpServers" %in% names(config)) {
    cli::cli_abort(
      cli::cli_abort(
        c(
          "Configuration processing failed.",
          i = "{.arg path} must have a top-level {.field mcpServers} entry."
        ),
        call = call
      )
    )
  }

  config$mcpServers
}


error_no_mcp_config <- function(call) {
  cli::cli_abort(
    c(
      "The acquaint MCP client configuration file does not exist.",
      i = "Supply a non-NULL file {.arg path} or create a file at the default 
           configuration location {.file {default_mcp_client_config()}}."
    ),
    call = call
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
  tools <- server$tools$tools

  tools_out <- list()
  for (i in seq_along(tools)) {
    tool <- tools[[i]]
    tool_arguments <- as_ellmer_types(tool)
    tools_out[[i]] <-
      do.call(
        ellmer::tool,
        c(
          list(
            .fun = tool_ref(
              server = server$name,
              tool = tool$name,
              arguments = names(tool_arguments)
            ),
            .description = tool$description,
            .name = tool$name
          ),
          tool_arguments
        )
      )
  }

  tools_out
}

as_ellmer_types <- function(tool) {
  properties <- tool$inputSchema$properties
  required_fields <- tool$inputSchema$required

  result <- list()
  for (prop_name in names(properties)) {
    result[[prop_name]] <- as_ellmer_type(
      prop_name,
      properties[[prop_name]],
      required_fields
    )
  }

  result
}

as_ellmer_type <- function(prop_name, prop_def, required_fields = character()) {
  type <- prop_def$type
  description <- prop_def$description
  is_required <- prop_name %in% required_fields

  if (length(type) == 0) {
    return(NULL)
  }

  switch(
    type,
    "string" = ellmer::type_string(
      description = description,
      required = is_required
    ),
    "number" = ellmer::type_number(
      description = description,
      required = is_required
    ),
    "integer" = ellmer::type_integer(
      description = description,
      required = is_required
    ),
    "boolean" = ellmer::type_boolean(
      description = description,
      required = is_required
    ),
    "array" = {
      if (!is.null(prop_def$items)) {
        items_type <- as_ellmer_type("", prop_def$items, required_fields)
        ellmer::type_array(
          description = description,
          items = items_type,
          required = is_required
        )
      } else {
        ellmer::type_array(
          description = description,
          items = ellmer::type_string(),
          required = is_required
        )
      }
    },
    "object" = {
      if (!is.null(prop_def$properties)) {
        obj_args <- list(.description = description, .required = is_required)
        for (obj_prop_name in names(prop_def$properties)) {
          obj_args[[obj_prop_name]] <- as_ellmer_type(
            obj_prop_name,
            prop_def$properties[[obj_prop_name]],
            required_fields
          )
        }
        do.call(ellmer::type_object, obj_args)
      } else {
        ellmer::type_object(.description = description, .required = is_required)
      }
    },
    ellmer::type_string(description = description, required = is_required)
  )
}

# the output of this function is the function that the ellmer tool will
# reference. it has the "right" argument formals and carries along the server
# and tool it's associated with; when the outputted function is called, it just
# invokes the right tool from `the$mcp_servers` with the supplied arguments
tool_ref <- function(server, tool, arguments) {
  f <- function() {}
  formals(f) <- setNames(
    rep(list(quote(expr = )), length(arguments)),
    arguments
  )

  body(f) <- substitute(
    {
      call_info <- match.call()
      tool_args <- lapply(call_info[-1], eval)
      do.call(
        call_tool,
        c(tool_args, list(server = server_val, tool = tool_val))
      )
    },
    list(server_val = server, tool_val = tool)
  )

  f
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
    return(jsonlite::parse_json(output[1]))
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
# This is a MAY in the protocol, so omitting.

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
