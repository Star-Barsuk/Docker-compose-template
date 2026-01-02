# =============================================================================
# ENV MAKEFILE (wrapper)
# =============================================================================

ENV_SCRIPT := $(ROOT_DIR)/scripts/bin/env.sh
LOG_LEVEL ?= INFO

.PHONY: env env-list env-status env-validate _help_env

env:
	@LOG_LEVEL="$(LOG_LEVEL)" $(ENV_SCRIPT) select || true

env-list:
	@LOG_LEVEL="$(LOG_LEVEL)" $(ENV_SCRIPT) list || true

env-status:
	@LOG_LEVEL="$(LOG_LEVEL)" $(ENV_SCRIPT) status || true

env-validate:
	@LOG_LEVEL="$(LOG_LEVEL)" $(ENV_SCRIPT) validate || true

_help_env:
	@echo "Environment commands:"
	@echo "  make env           Select environment"
	@echo "  make env-list      List available environments"
	@echo "  make env-status    Show active environment variables"
	@echo "  make env-validate  Validate active environment"
	@echo "Optional: LOG_LEVEL can be set (default INFO)"
