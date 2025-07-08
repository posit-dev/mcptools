if (is_new_ellmer()) {
  res <-
    list(
      tool_rnorm = ellmer::tool(
        fun = rnorm,
        description = "Draw numbers from a random normal distribution",
        arguments = list(
          n = ellmer::type_integer(
            "The number of observations. Must be a positive integer."
          ),
          mean = ellmer::type_number("The mean value of the distribution."),
          sd = ellmer::type_number(
            "The standard deviation of the distribution. Must be a non-negative number."
          )
        )
      )
    )
} else {
  res <-
    list(
      tool_rnorm = ellmer::tool(
        rnorm,
        "Draw numbers from a random normal distribution",
        n = ellmer::type_integer(
          "The number of observations. Must be a positive integer."
        ),
        mean = ellmer::type_number("The mean value of the distribution."),
        sd = ellmer::type_number(
          "The standard deviation of the distribution. Must be a non-negative number."
        ),
      )
    )
}


res
