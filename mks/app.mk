# =============================================================================
# APPLICATION MAKEFILE (wrapper)
# =============================================================================

.PHONY: app-run app-test app-lint app-shell _help_app

APP_SCRIPT := $(ROOT_DIR)/scripts/bin/app.sh

app-run:
	@$(APP_SCRIPT) run

app-test:
	@$(APP_SCRIPT) test

app-lint:
	@$(APP_SCRIPT) lint

app-shell:
	@$(APP_SCRIPT) shell

_help_app:
	@printf "$(GREEN)Application$(RESET)\n"
	@printf "  $(CYAN)app-run$(RESET)     Run application\n"
	@printf "  $(CYAN)app-test$(RESET)    Run tests\n"
	@printf "  $(CYAN)app-lint$(RESET)    Lint code\n"
	@printf "  $(CYAN)app-shell$(RESET)   Shell into app\n"
