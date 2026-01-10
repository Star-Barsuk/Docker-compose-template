# =============================================================================
# SECRETS MAKEFILE MODULE
# =============================================================================

.PHONY: secrets-check secrets-list secrets-generate \
	_help_secrets

# -----------------------------------------------------------------------------
# TARGETS
# -----------------------------------------------------------------------------
secrets-check:
	@bash $(SCRIPTS_DIR)/secrets.sh check

secrets-list:
	@bash $(SCRIPTS_DIR)/secrets.sh list

secrets-generate:
	@bash $(SCRIPTS_DIR)/secrets.sh generate $(and $(FORCE),FORCE=1)

# -----------------------------------------------------------------------------
# HELP
# -----------------------------------------------------------------------------
_help_secrets:
	@echo "---Secrets commands:"
	@echo "  make secrets-check     Validate secrets"
	@echo "  make secrets-list      List secrets"
	@echo "  make secrets-generate  Generate secrets (use FORCE=1 to regenerate)"
