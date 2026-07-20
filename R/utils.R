jsonrpc_response <- function(id, result = NULL, error = NULL) {
  if (!xor(is.null(result), is.null(error))) {
    warning("Either `result` or `error` must be provided, but not both.")
  }

  drop_nulls(list(
    jsonrpc = "2.0",
    id = id,
    result = result,
    error = error
  ))
}

# Create a named list, ensuring that it's a named list, even if empty.
named_list <- function(...) {
  res <- list(...)
  if (length(res) == 0) {
    # A way of creating an empty named list
    res <- list(a = 1)[0]
  }
  res
}

to_json <- function(x, ...) {
  jsonlite::toJSON(x, ..., auto_unbox = TRUE, null = "null")
}

is_string <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x)
}

is_absolute_path <- function(path) {
  grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)
}

split_envvar <- function(x) {
  if (!nzchar(x)) {
    return(character())
  }

  trimws(strsplit(x, ",", fixed = TRUE)[[1]])
}

first_nonempty_string <- function(...) {
  for (x in list(...)) {
    if (is_string(x) && nzchar(x)) {
      return(x)
    }
  }

  ""
}

url_origin <- function(x) {
  parsed <- url_parse_or_null(x)
  if (is.null(parsed$scheme) || is.null(parsed$hostname)) {
    return(NULL)
  }

  host <- parsed$hostname
  if (!is.null(parsed$port)) {
    host <- paste0(host, ":", parsed$port)
  }

  paste0(parsed$scheme, "://", host)
}

url_parse_or_null <- function(x) {
  tryCatch(
    httr2::url_parse(x),
    error = function(err) NULL
  )
}

# SSRF guard for server-side fetches of tool-supplied URLs: TRUE when `host` is
# an IP literal in a loopback, private, or link-local range, or resolves to
# loopback by name. curl normalizes octal/hex/integer IPv4 forms to
# dotted-decimal before we see the parsed host, so only dotted-quad and
# bracketed IPv6 literals need handling here. This is a literal-only block, not
# a DNS-rebinding defense: a hostname that resolves to a private address is not
# caught.
is_private_host_literal <- function(host) {
  host <- tolower(host %||% "")
  if (!nzchar(host)) {
    return(FALSE)
  }

  if (identical(host, "localhost") || endsWith(host, ".localhost")) {
    return(TRUE)
  }

  if (startsWith(host, "[") && endsWith(host, "]")) {
    host <- substr(host, 2L, nchar(host) - 1L)
  }

  if (grepl(":", host, fixed = TRUE)) {
    return(ipv6_is_private_or_loopback(host))
  }

  octets <- ipv4_literal_octets(host)
  if (!is.null(octets)) {
    return(ipv4_is_private_or_loopback(octets))
  }

  FALSE
}

is_loopback_host_literal <- function(host) {
  host <- tolower(host %||% "")
  if (!nzchar(host)) {
    return(FALSE)
  }

  if (identical(host, "localhost") || endsWith(host, ".localhost")) {
    return(TRUE)
  }

  if (startsWith(host, "[") && endsWith(host, "]")) {
    host <- substr(host, 2L, nchar(host) - 1L)
  }

  if (grepl(":", host, fixed = TRUE)) {
    return(ipv6_is_loopback(host))
  }

  octets <- ipv4_literal_octets(host)
  !is.null(octets) && octets[[1]] == 127L
}

ipv4_literal_octets <- function(host) {
  if (!grepl("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", host)) {
    return(NULL)
  }

  octets <- as.integer(strsplit(host, ".", fixed = TRUE)[[1]])
  if (any(octets > 255L)) {
    return(NULL)
  }

  octets
}

ipv4_is_private_or_loopback <- function(octets) {
  a <- octets[[1]]
  b <- octets[[2]]

  a == 0L || # 0.0.0.0/8 "this host"
    a == 10L || # 10.0.0.0/8 private
    a == 127L || # 127.0.0.0/8 loopback
    (a == 169L && b == 254L) || # 169.254.0.0/16 link-local
    (a == 172L && b >= 16L && b <= 31L) || # 172.16.0.0/12 private
    (a == 192L && b == 168L) # 192.168.0.0/16 private
}

ipv6_is_private_or_loopback <- function(host) {
  hextets <- ipv6_hextets(host)
  if (is.null(hextets)) {
    return(FALSE)
  }

  embedded <- ipv6_embedded_ipv4_octets(hextets)
  if (!is.null(embedded)) {
    return(ipv4_is_private_or_loopback(embedded))
  }

  first <- hextets[[1]]
  (first >= 0xfe80L && first <= 0xfebfL) || # fe80::/10 link-local
    (first >= 0xfc00L && first <= 0xfdffL) # fc00::/7 unique local
}

ipv6_is_loopback <- function(host) {
  hextets <- ipv6_hextets(host)
  if (is.null(hextets)) {
    return(FALSE)
  }

  if (all(hextets[1:7] == 0L) && hextets[[8]] == 1L) {
    return(TRUE)
  }

  embedded <- ipv6_embedded_ipv4_octets(hextets)
  !is.null(embedded) && embedded[[1]] == 127L
}

# The IPv4-mapped (::ffff:0:0/96) and deprecated IPv4-compatible (::/96) forms
# both carry a reachable IPv4 address in their final two hextets; surface it so
# the IPv4 classifier can be reused, catching e.g. ::ffff:a9fe:a9fe.
ipv6_embedded_ipv4_octets <- function(hextets) {
  is_mapped <- all(hextets[1:5] == 0L) && hextets[[6]] == 0xffffL
  is_compatible <- all(hextets[1:6] == 0L)
  if (!is_mapped && !is_compatible) {
    return(NULL)
  }

  c(
    hextets[[7]] %/% 256L, hextets[[7]] %% 256L,
    hextets[[8]] %/% 256L, hextets[[8]] %% 256L
  )
}

# Expand an IPv6 literal to its eight 16-bit hextets, resolving "::"
# zero-compression and any trailing embedded IPv4 dotted-quad. Returns NULL for
# anything that is not a well-formed IPv6 literal, so callers treat unparseable
# hosts as non-private (consistent with the literal-only contract above).
ipv6_hextets <- function(host) {
  # A zone id (e.g. fe80::1%eth0) scopes but does not change the address itself.
  host <- sub("%.*$", "", host)
  if (grepl("[^0-9a-f:.]", host) || grepl(":::", host, fixed = TRUE)) {
    return(NULL)
  }

  compressions <- gregexpr("::", host, fixed = TRUE)[[1]]
  n_compressions <- if (compressions[[1]] == -1L) 0L else length(compressions)
  if (n_compressions > 1L) {
    return(NULL)
  }

  if (n_compressions == 1L) {
    left <- ipv6_expand_groups(sub("::.*$", "", host), allow_ipv4_tail = FALSE)
    right <- ipv6_expand_groups(sub("^.*::", "", host), allow_ipv4_tail = TRUE)
    if (is.null(left) || is.null(right)) {
      return(NULL)
    }
    n_fill <- 8L - (length(left) + length(right))
    if (n_fill < 0L) {
      return(NULL)
    }
    return(c(left, rep(0L, n_fill), right))
  }

  hextets <- ipv6_expand_groups(host, allow_ipv4_tail = TRUE)
  if (is.null(hextets) || length(hextets) != 8L) {
    return(NULL)
  }
  hextets
}

ipv6_expand_groups <- function(x, allow_ipv4_tail) {
  if (!nzchar(x)) {
    return(integer(0))
  }

  groups <- strsplit(x, ":", fixed = TRUE)[[1]]
  n <- length(groups)
  hextets <- integer(0)
  for (i in seq_len(n)) {
    group <- groups[[i]]
    if (grepl(".", group, fixed = TRUE)) {
      octets <- if (allow_ipv4_tail && i == n) ipv4_literal_octets(group) else NULL
      if (is.null(octets)) {
        return(NULL)
      }
      hextets <- c(
        hextets,
        octets[[1]] * 256L + octets[[2]],
        octets[[3]] * 256L + octets[[4]]
      )
    } else {
      if (!grepl("^[0-9a-f]{1,4}$", group)) {
        return(NULL)
      }
      hextets <- c(hextets, strtoi(group, base = 16L))
    }
  }

  hextets
}

constant_time_equal <- function(x, y) {
  if (!is_string(x) || !is_string(y)) {
    return(FALSE)
  }

  x <- as.integer(charToRaw(enc2utf8(x)))
  y <- as.integer(charToRaw(enc2utf8(y)))
  n <- max(length(x), length(y))
  diff <- bitwXor(length(x), length(y))

  for (i in seq_len(n)) {
    x_i <- if (i <= length(x)) x[[i]] else 0L
    y_i <- if (i <= length(y)) y[[i]] else 0L
    diff <- bitwOr(diff, bitwXor(x_i, y_i))
  }

  identical(diff, 0L)
}

interactive <- NULL

mcptools_server_log <- function() {
  Sys.getenv("MCPTOOLS_SERVER_LOG", tempfile(fileext = ".txt"))
}

mcptools_client_log <- function() {
  Sys.getenv("MCPTOOLS_CLIENT_LOG", tempfile(fileext = ".txt"))
}

# from rstudio/reticulate
is_unix <- function() {
  identical(.Platform$OS.type, "unix")
}

is_fedora <- function() {
  if (is_unix() && file.exists("/etc/os-release")) {
    os_info <- readLines("/etc/os-release")
    any(grepl("Fedora", os_info))
  } else {
    FALSE
  }
}
