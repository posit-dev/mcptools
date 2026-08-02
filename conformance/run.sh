#!/usr/bin/env bash
# Run the official MCP conformance suite (server mode) against the forked
# mcptools everything-server.
#
# Boots conformance/everything-server.R on a local port, waits for it to
# accept requests, runs the conformance harness, saves the output, and tears
# the server down.
#
# Env overrides:
#   MCP_HOST              bind host (default 127.0.0.1)
#   MCP_PORT              bind port (default 3001)
#   SPEC_VERSION          spec version to test (default 2025-11-25)
#   SUITE                 conformance suite (default all)
#   CONFORMANCE_VERSION   npm harness version (defaults per spec version)
#   EXPECTED              expected-failures file (version-specific by default)
#   OUT                   output file (default conformance/last-run-<spec>.txt)
#   SERVER_LOG            server log (default conformance/server-<spec>.log)
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

# ---- Library isolation -----------------------------------------------------
# Load the worktree-local build (see Makefile `install`) ahead of the shared
# user library so parallel worktrees don't load each other's package. Capture
# the *original* libpaths first (for dependency resolution), before overriding.
RLIB="${RLIB:-$REPO/.Rlib}"
if [ -d "$RLIB" ]; then
  ORIG_LIBS="$(Rscript -e 'cat(paste(.libPaths(), collapse=":"))' 2>/dev/null || true)"
  export R_LIBS_USER="$RLIB:$ORIG_LIBS"
fi

HOST="${MCP_HOST:-127.0.0.1}"
# Pick an ephemeral port by default so concurrent runs don't collide.
if [ -n "${MCP_PORT:-}" ]; then
  PORT="$MCP_PORT"
else
  PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()' 2>/dev/null || true)"
  [ -z "$PORT" ] && PORT=$(( (RANDOM % 20000) + 20000 ))
fi
SPEC="${SPEC_VERSION:-2025-11-25}"
SUITE="${SUITE:-all}"
if [ "${CONFORMANCE_VERSION+x}" = "x" ]; then
  CONF_VER="$CONFORMANCE_VERSION"
elif [ "$SPEC" = "2026-07-28" ]; then
  CONF_VER="0.2.0-alpha.10"
else
  CONF_VER="0.1.16"
fi
OUT="${OUT:-$HERE/last-run-${SPEC}.txt}"
SERVER_LOG="${SERVER_LOG:-$HERE/server-${SPEC}.log}"
# Expected-failures baseline (the ratchet). Set EXPECTED="" to disable.
if [ "${EXPECTED+x}" = "x" ]; then
  EXPECTED_FILE="$EXPECTED"
elif [ "$SPEC" = "2026-07-28" ]; then
  EXPECTED_FILE="$HERE/expected-failures-2026-07-28.yml"
else
  EXPECTED_FILE="$HERE/expected-failures.yml"
fi

echo "[run] launching everything-server on ${HOST}:${PORT}"
MCP_HOST="$HOST" MCP_PORT="$PORT" Rscript "$HERE/everything-server.R" >"$SERVER_LOG" 2>&1 &
SERVER_PID=$!

cleanup() { kill "$SERVER_PID" 2>/dev/null || true; }
trap cleanup EXIT

echo "[run] waiting for http://${HOST}:${PORT}/mcp ..."
ready=0
for _ in $(seq 1 120); do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    echo "[run] ERROR: server process exited early; log follows:" >&2
    cat "$SERVER_LOG" >&2
    exit 1
  fi
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 2 -X POST "http://${HOST}:${PORT}/mcp" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H "MCP-Protocol-Version: ${SPEC}" \
    -d '{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"'"${SPEC}"'","capabilities":{},"clientInfo":{"name":"readiness","version":"0"}}}' 2>/dev/null || true)"
  if [ -n "$code" ] && [ "$code" != "000" ]; then ready=1; break; fi
  sleep 0.5
done
if [ "$ready" -ne 1 ]; then
  echo "[run] ERROR: server did not become ready" >&2
  cat "$SERVER_LOG" >&2
  exit 1
fi

EXPECTED_ARGS=()
if [ -n "$EXPECTED_FILE" ] && [ -f "$EXPECTED_FILE" ]; then
  EXPECTED_ARGS=(--expected-failures "$EXPECTED_FILE")
  echo "[run] using expected-failures baseline: ${EXPECTED_FILE}"
fi

echo "[run] running conformance@${CONF_VER} server suite=${SUITE} spec=${SPEC}"
npx -y "@modelcontextprotocol/conformance@${CONF_VER}" server \
  --url "http://${HOST}:${PORT}/mcp" \
  --suite "$SUITE" \
  --spec-version "$SPEC" \
  "${EXPECTED_ARGS[@]}" | tee "$OUT"
RC=${PIPESTATUS[0]}

echo "[run] harness exit=${RC}; output saved to ${OUT}"
exit "$RC"
