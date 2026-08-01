mrtr_tool_names <- c(
  "test_input_required_result_elicitation",
  "test_input_required_result_sampling",
  "test_input_required_result_list_roots",
  "test_input_required_result_request_state",
  "test_input_required_result_multiple_inputs",
  "test_input_required_result_multi_round",
  "test_input_required_result_tampered_state",
  "test_input_required_result_capabilities"
)

stateless_mrtr_response <- function(data) {
  if (identical(data$method, "prompts/get")) {
    if (identical(data$params$name, "test_input_required_result_prompt")) {
      result <- mrtr_prompt_result(data)
      if (inherits(result, "jsonrpc_error")) {
        return(jsonrpc_response(data$id, error = unclass(result)))
      }
      return(jsonrpc_response(
        data$id,
        result = result
      ))
    }
    return(NULL)
  }

  tool_name <- data$params$name
  if (
    !identical(data$method, "tools/call") ||
      !is_string(tool_name) ||
      !tool_name %in% mrtr_tool_names
  ) {
    return(NULL)
  }

  result <- mrtr_tool_result(data)
  if (inherits(result, "jsonrpc_error")) {
    return(jsonrpc_response(data$id, error = unclass(result)))
  }
  jsonrpc_response(data$id, result = result)
}

mrtr_tool_result <- function(data) {
  name <- data$params$name

  switch(
    name,
    test_input_required_result_elicitation = mrtr_single_input_result(
      data,
      key = "user_name",
      capability = "elicitation",
      request = mrtr_elicitation_request(
        "What is your name?",
        "name",
        "Your name"
      ),
      complete_text = "Elicitation input received"
    ),
    test_input_required_result_sampling = mrtr_single_input_result(
      data,
      key = "capital_question",
      capability = "sampling",
      request = mrtr_sampling_request(
        "What is the capital of France?"
      ),
      complete_text = "Sampling input received"
    ),
    test_input_required_result_list_roots = mrtr_single_input_result(
      data,
      key = "client_roots",
      capability = "roots",
      request = mrtr_roots_request(),
      complete_text = "Roots input received"
    ),
    test_input_required_result_request_state = mrtr_request_state_result(data),
    test_input_required_result_multiple_inputs = mrtr_multiple_inputs_result(
      data
    ),
    test_input_required_result_multi_round = mrtr_multi_round_result(data),
    test_input_required_result_tampered_state = mrtr_tampered_state_result(
      data
    ),
    test_input_required_result_capabilities = mrtr_capabilities_result(data)
  )
}

mrtr_single_input_result <- function(
  data,
  key,
  capability,
  request,
  complete_text
) {
  capability_error <- mrtr_capability_error(data, capability)
  if (!is.null(capability_error)) {
    return(capability_error)
  }

  if (mrtr_has_response(data$params$inputResponses, key)) {
    return(mrtr_complete_result(complete_text))
  }

  mrtr_input_required(setNames(list(request), key))
}

mrtr_request_state_result <- function(data) {
  capability_error <- mrtr_capability_error(data, "elicitation")
  if (!is.null(capability_error)) {
    return(capability_error)
  }

  responses <- data$params$inputResponses
  expected_state <- mrtr_request_state(
    "test_input_required_result_request_state",
    1L
  )
  if (mrtr_has_response(responses, "confirm")) {
    if (!mrtr_state_matches(data$params$requestState, expected_state)) {
      return(mrtr_invalid_state_error())
    }
    return(mrtr_complete_result("Request state accepted"))
  }

  mrtr_input_required(
    list(confirm = mrtr_confirmation_request("Continue the workflow?")),
    request_state = expected_state
  )
}

mrtr_multiple_inputs_result <- function(data) {
  required <- c("elicitation", "sampling", "roots")
  capability_error <- mrtr_capability_error(data, required)
  if (!is.null(capability_error)) {
    return(capability_error)
  }

  requests <- list(
    confirmation = mrtr_confirmation_request("Confirm this operation"),
    sample = mrtr_sampling_request("Summarize the confirmed operation"),
    roots = mrtr_roots_request()
  )
  responses <- data$params$inputResponses
  expected_state <- mrtr_request_state(
    "test_input_required_result_multiple_inputs",
    1L
  )
  if (is.list(responses) && length(responses)) {
    if (!mrtr_state_matches(data$params$requestState, expected_state)) {
      return(mrtr_invalid_state_error())
    }
    if (all(vapply(
      names(requests),
      function(key) mrtr_has_response(responses, key),
      logical(1)
    ))) {
      return(mrtr_complete_result("All requested inputs received"))
    }
  }

  mrtr_input_required(requests, request_state = expected_state)
}

mrtr_multi_round_result <- function(data) {
  capability_error <- mrtr_capability_error(data, "elicitation")
  if (!is.null(capability_error)) {
    return(capability_error)
  }

  responses <- data$params$inputResponses
  round_one_state <- mrtr_request_state(
    "test_input_required_result_multi_round",
    1L
  )
  round_two_state <- mrtr_request_state(
    "test_input_required_result_multi_round",
    2L
  )

  if (!is.list(responses) || !length(responses)) {
    return(mrtr_input_required(
      list(step1 = mrtr_confirmation_request("Complete step one?")),
      request_state = round_one_state
    ))
  }

  if (mrtr_state_matches(data$params$requestState, round_one_state)) {
    if (!mrtr_has_response(responses, "step1")) {
      return(mrtr_input_required(
        list(step1 = mrtr_confirmation_request("Complete step one?")),
        request_state = round_one_state
      ))
    }
    return(mrtr_input_required(
      list(step2 = mrtr_confirmation_request("Complete step two?")),
      request_state = round_two_state
    ))
  }

  if (mrtr_state_matches(data$params$requestState, round_two_state)) {
    if (mrtr_has_response(responses, "step2")) {
      return(mrtr_complete_result("Multi-round workflow completed"))
    }
    return(mrtr_input_required(
      list(step2 = mrtr_confirmation_request("Complete step two?")),
      request_state = round_two_state
    ))
  }

  mrtr_invalid_state_error()
}

mrtr_tampered_state_result <- function(data) {
  capability_error <- mrtr_capability_error(data, "elicitation")
  if (!is.null(capability_error)) {
    return(capability_error)
  }

  expected_state <- mrtr_request_state(
    "test_input_required_result_tampered_state",
    1L
  )
  responses <- data$params$inputResponses
  if (is.list(responses) && length(responses)) {
    if (!mrtr_state_matches(data$params$requestState, expected_state)) {
      return(mrtr_invalid_state_error())
    }
    return(mrtr_complete_result("Request state accepted"))
  }

  mrtr_input_required(
    list(confirm = mrtr_confirmation_request("Confirm this operation")),
    request_state = expected_state
  )
}

mrtr_capabilities_result <- function(data) {
  capabilities <- stateless_client_capabilities(data)
  requests <- named_list()

  if (!is.null(capabilities$sampling)) {
    requests$sampling <- mrtr_sampling_request(
      "Describe the client's sampling support"
    )
  }
  if (!is.null(capabilities$elicitation)) {
    requests$elicitation <- mrtr_elicitation_request(
      "Provide a short confirmation",
      "confirmation",
      "Confirmation"
    )
  }
  if (!is.null(capabilities$roots)) {
    requests$roots <- mrtr_roots_request()
  }

  if (!length(requests)) {
    return(mrtr_capability_error(
      data,
      c("sampling", "elicitation", "roots")
    ))
  }
  mrtr_input_required(requests)
}

mrtr_prompt_result <- function(data) {
  capability_error <- mrtr_capability_error(data, "elicitation")
  if (!is.null(capability_error)) {
    return(capability_error)
  }

  params <- data$params
  if (mrtr_has_response(params$inputResponses, "user_context")) {
    return(list(messages = list(list(
      role = "user",
      content = list(
        type = "text",
        text = "Prompt context received"
      )
    ))))
  }

  mrtr_input_required(list(
    user_context = mrtr_elicitation_request(
      "What context should this prompt use?",
      "context",
      "Prompt context"
    )
  ))
}

mrtr_input_required <- function(input_requests, request_state = NULL) {
  drop_nulls(list(
    resultType = "input_required",
    inputRequests = input_requests,
    requestState = request_state
  ))
}

mrtr_complete_result <- function(text) {
  list(content = list(list(type = "text", text = text)))
}

mrtr_elicitation_request <- function(message, property, description) {
  list(
    method = "elicitation/create",
    params = list(
      mode = "form",
      message = message,
      requestedSchema = list(
        type = "object",
        properties = setNames(list(list(
          type = "string",
          description = description
        )), property),
        required = list(property)
      )
    )
  )
}

mrtr_confirmation_request <- function(message) {
  list(
    method = "elicitation/create",
    params = list(
      mode = "form",
      message = message,
      requestedSchema = list(
        type = "object",
        properties = list(confirmed = list(type = "boolean")),
        required = list("confirmed")
      )
    )
  )
}

mrtr_sampling_request <- function(message) {
  list(
    method = "sampling/createMessage",
    params = list(
      messages = list(list(
        role = "user",
        content = list(type = "text", text = message)
      )),
      maxTokens = 64L
    )
  )
}

mrtr_roots_request <- function() {
  list(method = "roots/list", params = named_list())
}

mrtr_has_response <- function(input_responses, key) {
  is.list(input_responses) && is.list(input_responses[[key]])
}

mrtr_capability_error <- function(data, capabilities) {
  client_capabilities <- stateless_client_capabilities(data)
  missing <- capabilities[vapply(
    capabilities,
    function(capability) is.null(client_capabilities[[capability]]),
    logical(1)
  )]
  if (!length(missing)) {
    return(NULL)
  }

  required <- setNames(
    rep(list(named_list()), length(missing)),
    missing
  )
  jsonrpc_error(
    -32021L,
    "Missing required client capability",
    data = list(requiredCapabilities = required)
  )
}

mrtr_request_state <- function(workflow, round) {
  if (is.null(the$mrtr_state_secret)) {
    the$mrtr_state_secret <- openssl::rand_bytes(32L)
  }

  payload <- paste(workflow, round, sep = ":")
  encoded <- openssl::base64_encode(charToRaw(payload))
  signature <- as.character(openssl::sha256(
    charToRaw(encoded),
    key = the$mrtr_state_secret
  ))
  paste(encoded, signature, sep = ".")
}

mrtr_state_matches <- function(actual, expected) {
  constant_time_equal(actual, expected)
}

mrtr_invalid_state_error <- function() {
  jsonrpc_error(-32602L, "Invalid or tampered requestState")
}
