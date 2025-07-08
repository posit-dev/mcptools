the <- new_environment()
the$server_processes <- list()

# ellmer 0.3.0 --------------------------------------------------------------
# the ellmer 0.3.0 release will make a number of breaking changes.
# we'll include a few functions to future-proof the initial release of mcptools
# for that package release (#52).
is_new_ellmer <- function() {
  packageVersion("ellmer") >= "0.2.1.9000"
}

tool_fun <- function(tool) {
  if (is_new_ellmer()) {
    return(tool)
  }

  tool@fun
}
