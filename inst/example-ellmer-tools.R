list(
  tool_rnorm = ellmer::tool(
    rnorm,
    "Drawn numbers from a random normal distribution",
    n = ellmer::type_integer(
      "The number of observations. Must be a positive integer."
    ),
    mean = ellmer::type_number("The mean value of the distribution."),
    sd = ellmer::type_number(
      "The standard deviation of the distribution. Must be a non-negative number."
    ),
  )
)
