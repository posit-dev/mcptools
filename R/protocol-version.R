supported_protocol_versions <- c(
  "2024-11-05",
  "2025-03-26",
  "2025-06-18",
  "2025-11-25"
)

latest_protocol_version <- supported_protocol_versions[
  length(supported_protocol_versions)
]

negotiate_protocol_version <- function(client_version) {
  if (client_version %in% supported_protocol_versions) {
    client_version
  } else {
    latest_protocol_version
  }
}

protocol_version_gte <- function(version, reference) {
  version >= reference
}

protocol_version_lt <- function(version, reference) {
  version < reference
}
