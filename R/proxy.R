#' @rdname mcp
#' @export
mcp_proxy <- function() {
  # TODO: should this actually be a check for being called within Rscript or not?
  check_not_interactive()

  mcp_proxy_impl()
}

# This R script is a proxy. It takes input on stdin, and when the input forms
# valid JSON, it will POST the JSON to the server, then when it receives the
# response, it will print the response to stdout.
mcp_proxy_impl <- function() {
  url <- paste0("http://localhost:", acquaint_port(), collapse = "")
  logcat("START", append = FALSE)
  buf <- ""

  # Note that we're using file("stdin") instead of stdin() because the former
  # blocks but the latter does not when used with readLines(). If it doesn't block,
  # the loop will poll continuously and use 100% CPU.
  f <- file("stdin")
  open(f, blocking = TRUE)

  while (TRUE) {
    line <- readLines(f, n = 1)

    if (length(line) == 0) {
      next
    }

    logcat(line)

    buf <- paste0(c(buf, line), collapse = "\n")

    data <- NULL

    tryCatch(
      {
        data <- jsonlite::fromJSON(buf)
      },
      error = function(e) {
        # Invalid JSON
      }
    )
    if (is.null(data)) {
      next
    }
    # If we made it here, it's valid JSON

    if (identical(data$method, "initialize")) {
      res <- jsonrpc_response_proxy(data$id, capabilities())
      cat_json(res)

    } else if (identical(data$method, "notifications/initialized")) {
      # This is confirmation from the client; do nothing
    
    } else if (identical(data$method, "prompts/list")) {
      # No prompts yet
      cat_json(jsonrpc_response_proxy(data$id, list(prompts = list())))

    } else if (identical(data$method, "resources/list")) {
      # No resources yet
      cat_json(jsonrpc_response_proxy(data$id, list(resources = list())))

    } else if (identical(data$method, "tools/list")) {
      res <- jsonrpc_response_proxy(
        data$id,
        list(
          tools = get_all_btw_tools()
        )
      )
      # cat(to_json(res), "\n", sep = "", file = stderr())
      cat_json(res)
    } else {
      # For all other messages, forward them to the server
      result <- post_request(buf, url)

      response_text <- rawToChar(result$content)
      logcat(response_text)
      
      # The response_text is alredy JSON, so we'll use cat() instead of cat_json()
      cat(response_text, "\n", sep = "")
      # cat("Response status:", result$status_code, "\n", file = stderr())
      # cat("Response body:", response_text, "\n", file = stderr())
    }

    buf <- ""
  }
}

# This process will be launched by the MCP client, so stdout/stderr aren't
# visible. This function will log output to the `logfile` so that you can view
# it.
logcat <- function(x, ..., append = TRUE) {
  log_file <- acquaint_log_file()
  cat(x, "\n", sep = "", append = append, file = log_file)
}

post_request <- function(json_data, url) {
  h <- curl::new_handle() 
  h <- curl::handle_setheaders(h, "Content-Type" = "application/json")
  h <- curl::handle_setopt(h, customrequest = "POST")
  h <- curl::handle_setopt(h, postfields = json_data)

  result <- curl::curl_fetch_memory(url, h)

  return(result)
}

# Wrap `x` in a jsonrpc-formatted object. This also includes the id.
jsonrpc_response_proxy <- function(id, x) {
  list(
    jsonrpc = "2.0",
    id = id,
    result = x
  )
}

cat_json <- function(x) {
  cat(to_json(x), "\n", sep = "")
}

capabilities <- function() {
  list(
    protocolVersion = "2024-11-05",
    capabilities = list(
      # logging = named_list(),
      prompts = named_list(
        listChanged = FALSE
      ),
      resources = named_list(
        subscribe = FALSE,
        listChanged = FALSE
      ),
      tools = named_list(
        listChanged = FALSE
      )
    ),
    serverInfo = list(
      name = "R acquaint server",
      version = "0.0.1"
    ),
    instructions = "This provides information about a running R session."
  )
}

# Hacky way of getting tools from btw
get_all_btw_tools <- function() {
  dummy_provider <- ellmer::Provider("dummy", "dummy", "dummy")

  tools <- lapply(unname(btw:::.btw_tools), function(tool_obj) {
    tool <- tool_obj$tool()

    if (is.null(tool)) {
      return(NULL)
    }

    inputSchema <- compact(ellmer:::as_json(dummy_provider, tool@arguments))
    # This field is present but shouldn't be
    inputSchema$description <- NULL

    list(
      name = tool@name,
      description = tool@description,
      inputSchema = inputSchema
    )
  })

  compact(tools)
}

compact <- function(.x) {
  Filter(length, .x)
}

check_not_interactive <- function(call = caller_env()) {
  if (interactive()) {
    cli::cli_abort(
      c(
      "This function is not intended for interactive use.",
      "i" = "See {.help {.fn mcp_proxy}} for instructions on configuring this
       function with applications"
      ),
      call = call
    )
  }
}
