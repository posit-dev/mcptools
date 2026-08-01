# r-mcp — conformance-first R MCP SDK (fork of posit-dev/mcptools)
#
# Common developer targets. Requires: R (with package deps installed) and
# Node.js (for the conformance harness via npx).
#
# Isolation: the package is installed into a worktree-local library ($(RLIB))
# and loaded from there ahead of the shared user library. This lets multiple
# parallel worktrees/sessions build and conformance-test their own source
# without clobbering each other's install in the shared library.

.PHONY: help install deps conformance conformance-all \
	conformance-2025-11-25 conformance-2026-07-28 \
	everything-server clean-conformance

# Worktree-local package library (git-ignored).
RLIB := $(CURDIR)/.Rlib
CONFORMANCE_2025_VERSION ?= 0.1.16
CONFORMANCE_2026_VERSION ?= 0.2.0-alpha.10

help:
	@echo "Targets:"
	@echo "  make install            R CMD INSTALL the fork into a local library ($(RLIB))"
	@echo "  make deps               install R package dependencies"
	@echo "  make everything-server  run the conformance everything-server (foreground)"
	@echo "  make conformance        install + run both supported server conformance suites"
	@echo "  make conformance-2025-11-25  run the stateful server suite"
	@echo "  make conformance-2026-07-28  run the stateless server suite"
	@echo ""
	@echo "Overrides: SUITE=all MCP_PORT=<port> CONFORMANCE_2025_VERSION=<version> CONFORMANCE_2026_VERSION=<version>"

deps:
	Rscript -e 'if (!requireNamespace("pak", quietly=TRUE)) install.packages("pak", repos="https://cloud.r-project.org"); pak::local_install_deps(".")'

install:
	@mkdir -p "$(RLIB)"
	ORIG_LIBS="$$(Rscript -e 'cat(paste(.libPaths(), collapse=":"))')"; \
	  R_LIBS_USER="$(RLIB):$$ORIG_LIBS" \
	  R CMD INSTALL --no-docs --no-multiarch --library="$(RLIB)" .

everything-server:
	@mkdir -p "$(RLIB)"
	ORIG_LIBS="$$(Rscript -e 'cat(paste(.libPaths(), collapse=":"))')"; \
	  R_LIBS_USER="$(RLIB):$$ORIG_LIBS" Rscript conformance/everything-server.R

conformance: conformance-all

conformance-all: install
	RLIB="$(RLIB)" SPEC_VERSION=2025-11-25 \
	  CONFORMANCE_VERSION="$(CONFORMANCE_2025_VERSION)" \
	  EXPECTED="$(CURDIR)/conformance/expected-failures.yml" \
	  OUT="$(CURDIR)/conformance/last-run-2025-11-25.txt" \
	  SERVER_LOG="$(CURDIR)/conformance/server-2025-11-25.log" \
	  bash conformance/run.sh
	RLIB="$(RLIB)" SPEC_VERSION=2026-07-28 \
	  CONFORMANCE_VERSION="$(CONFORMANCE_2026_VERSION)" \
	  EXPECTED="$(CURDIR)/conformance/expected-failures-2026-07-28.yml" \
	  OUT="$(CURDIR)/conformance/last-run-2026-07-28.txt" \
	  SERVER_LOG="$(CURDIR)/conformance/server-2026-07-28.log" \
	  bash conformance/run.sh

conformance-2025-11-25: install
	RLIB="$(RLIB)" SPEC_VERSION=2025-11-25 \
	  CONFORMANCE_VERSION="$(CONFORMANCE_2025_VERSION)" \
	  EXPECTED="$(CURDIR)/conformance/expected-failures.yml" \
	  bash conformance/run.sh

conformance-2026-07-28: install
	RLIB="$(RLIB)" SPEC_VERSION=2026-07-28 \
	  CONFORMANCE_VERSION="$(CONFORMANCE_2026_VERSION)" \
	  EXPECTED="$(CURDIR)/conformance/expected-failures-2026-07-28.yml" \
	  bash conformance/run.sh
