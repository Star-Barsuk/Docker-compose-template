# =============================================================================
# APPLICATION MAKEFILE
# =============================================================================

.PHONY: app-run \
	app-test \
	app-lint \
	app-shell \
	_help_app

app-run:
	$(call EXEC,Run application,\
		@# Run app locally or via docker profile \
	)

app-test:
	$(call EXEC,Run tests,\
		@# Test runner \
	)

app-lint:
	$(call EXEC,Lint,\
		@# Static analysis \
	)

app-shell:
	$(call EXEC,App shell,\
		@# Shell inside app container or venv \
	)

_help_app:
	@printf "$(GREEN)Application$(RESET)\n"
	@printf "  $(CYAN)app-run$(RESET)     Run application\n"
	@printf "  $(CYAN)app-test$(RESET)    Run tests\n"
	@printf "  $(CYAN)app-lint$(RESET)    Lint code\n"
	@printf "  $(CYAN)app-shell$(RESET)   Shell into app\n"
