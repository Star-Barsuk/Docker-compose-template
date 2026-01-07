# =============================================================================
# APPLICATION MAKEFILE MODULE
# =============================================================================

.PHONY: run check-deps clean \
        shell lint format check fix \
        sync \
	app-help _help_app

# -----------------------------------------------------------------------------
# DEVELOPMENT ENVIRONMENT
# -----------------------------------------------------------------------------
check-deps:
	@bash $(SCRIPTS_DIR)/app.sh check-deps

clean:
	@bash $(SCRIPTS_DIR)/app.sh clean

# -----------------------------------------------------------------------------
# UV-SPECIFIC COMMANDS
# -----------------------------------------------------------------------------
sync:
	@bash $(SCRIPTS_DIR)/app.sh uv-sync

sync-dev:
	@bash $(SCRIPTS_DIR)/app.sh uv-sync --dev

# -----------------------------------------------------------------------------
# APPLICATION
# -----------------------------------------------------------------------------
run:
	@bash $(SCRIPTS_DIR)/app.sh run

shell:
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
	@echo "  make check-deps           Check dependency status"
	@echo "  make clean                Clean build artifacts and caches"
	@echo ""
	@echo "UV-Specific:"
	@echo "  make sync              Sync dependencies with uv"
	@echo "  make sync-dev          Sync with development dependencies"
	@echo ""
	@echo "Application:"
	@echo "  make run                  Run application"
	@echo "  make shell                Start Python REPL with project context"
	@echo ""
	@echo "Code Quality (Ruff):"
	@echo "  make lint                 Lint code (src/ scripts/)"
	@echo "  make format               Format code"
	@echo "  make check                Comprehensive check (format + lint)"
	@echo "  make fix                  Auto-fix issues (format + fix)"
	@echo ""
	@echo "Help:"
	@echo "  make app-help                 Show detailed help"
