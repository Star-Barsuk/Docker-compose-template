# =============================================================================
# APPLICATION MAKEFILE MODULE
# =============================================================================

.PHONY: app-run app-test app-lint app-shell _help_app

app-run:
	@bash $(SCRIPTS_DIR)/app.sh run

app-test:
	@bash $(SCRIPTS_DIR)/app.sh test

app-lint:
	@bash $(SCRIPTS_DIR)/app.sh lint

app-shell:
	@bash $(SCRIPTS_DIR)/app.sh shell

_help_app:
	@echo "Application commands:"
	@echo "  make app-run       Run application"
	@echo "  make app-test      Run tests"
	@echo "  make app-lint      Lint code"
	@echo "  make app-shell     Shell into app"
