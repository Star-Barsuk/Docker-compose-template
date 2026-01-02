# =============================================================================
# SECRETS MAKEFILE (wrapper)
# =============================================================================

.PHONY: secrets-check secrets-list secrets-generate _help_secrets

SECRETS_SCRIPT := $(ROOT_DIR)/scripts/bin/secrets.sh

secrets-check:
	@$(SECRETS_SCRIPT) check || true

secrets-list:
	@$(SECRETS_SCRIPT) list || true

secrets-generate:
	@$(SECRETS_SCRIPT) generate $(and $(FORCE),FORCE=1) || true

_help_secrets:
	@printf "$(GREEN)Secrets$(RESET)\n"
	@printf " $(CYAN)secrets-check$(RESET)     Validate secrets\n"
	@printf " $(CYAN)secrets-list$(RESET)      List secrets\n"
	@printf " $(CYAN)secrets-generate$(RESET)  Generate secrets (use FORCE=1 to regenerate)\n"
