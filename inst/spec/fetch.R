# The full plain-text spec is kept in inst/spec for use by coding agents.
# Update it by calling this function.
fetch_spec <- function(revision = "2025-06-18") {
  base_url <- sprintf(
    "https://modelcontextprotocol.io/specification/%s",
    revision
  )

  files <- c(
    "basic.md",
    "basic/lifecycle.md",
    "basic/transports.md",
    "basic/authorization.md"
  )

  dest_dir <- system.file("spec", package = "mcptools")
  if (dest_dir == "") {
    dest_dir <- "inst/spec"
  }

  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE)
  }

  for (file in files) {
    url <- file.path(base_url, file)
    dest_file <- file.path(dest_dir, basename(file))
    download.file(url, dest_file, quiet = FALSE, mode = "wb")
  }

  invisible(dest_dir)
}
