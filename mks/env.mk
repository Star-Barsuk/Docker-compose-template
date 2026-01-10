# =============================================================================
# ENVIRONMENT MAKEFILE MODULE
# =============================================================================

.PHONY: env env-list env-status env-validate \
	_help_env

# -----------------------------------------------------------------------------
# TARGETS
# -----------------------------------------------------------------------------
env:
	@bash $(SCRIPTS_DIR)/env.sh select

env-list:
	@bash $(SCRIPTS_DIR)/env.sh list

env-status:
	@bash $(SCRIPTS_DIR)/env.sh status

env-validate:
	@bash $(SCRIPTS_DIR)/env.sh validate

# -----------------------------------------------------------------------------
# HELP
# -----------------------------------------------------------------------------
_help_env:
	@echo "---Environment commands:"
	@echo "  make env           Select environment"
	@echo "  make env-list      List available environments"
	@echo "  make env-status    Show active environment variables"
	@echo "  make env-validate  Validate active environment"
