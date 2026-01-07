# =============================================================================
# APPLICATION MAKEFILE MODULE
# =============================================================================

.PHONY: app-run app-check-deps app-clean \
        app-shell \
	lint format check fix \
        app-sync app-sync-dev \
	app-help _help_app

# -----------------------------------------------------------------------------
# DEVELOPMENT ENVIRONMENT
# -----------------------------------------------------------------------------
app-check-deps:
	@bash $(SCRIPTS_DIR)/app.sh check-deps

app-clean:
	@bash $(SCRIPTS_DIR)/app.sh clean

# -----------------------------------------------------------------------------
# UV-SPECIFIC COMMANDS
# -----------------------------------------------------------------------------
app-sync:
	@bash $(SCRIPTS_DIR)/app.sh uv-sync

app-sync-dev:
	@bash $(SCRIPTS_DIR)/app.sh uv-sync --dev

# -----------------------------------------------------------------------------
# APPLICATION
# -----------------------------------------------------------------------------
app-run:
	@bash $(SCRIPTS_DIR)/app.sh run

app-shell:
	@bash $(SCRIPTS_DIR)/app.sh shell

# -----------------------------------------------------------------------------
# CODE QUALITY (RUFF)
# -----------------------------------------------------------------------------
lint:
	@bash $(SCRIPTS_DIR)/app.sh lint

format:
	@bash $(SCRIPTS_DIR)/app.sh format

check:
	@bash $(SCRIPTS_DIR)/app.sh check

fix:
	@bash $(SCRIPTS_DIR)/app.sh fix

# -----------------------------------------------------------------------------
# HELP
# -----------------------------------------------------------------------------
app-help:
	@bash $(SCRIPTS_DIR)/app.sh help

_help_app:
	@echo "Application commands:"
	@echo ""
	@echo "Development Environment:"
	@echo "  make app-check-deps           Check dependency status"
	@echo "  make app-clean                Clean build artifacts and caches"
	@echo ""
	@echo "UV-Specific:"
	@echo "  make app-sync              Sync dependencies with uv"
	@echo "  make app-sync-dev          Sync with development dependencies"
	@echo ""
	@echo "Application:"
	@echo "  make app-run                  Run application"
	@echo "  make app-shell                Start Python REPL with project context"
	@echo ""
	@echo "Code Quality (Ruff):"
	@echo "  make lint                 Lint code (src/ scripts/)"
	@echo "  make format               Format code"
	@echo "  make check                Comprehensive check (format + lint)"
	@echo "  make fix                  Auto-fix issues (format + fix)"
	@echo ""
	@echo "Help:"
	@echo "  make app-help                 Show detailed help"
