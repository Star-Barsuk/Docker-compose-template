# === Config ===
PROJECT := database-module
PYTHON := uv run python
RUFF := uv run ruff

# === Colors ===
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[1;33m
BLUE=\033[0;34m
MAGENTA=\033[0;35m
CYAN=\033[0;36m
WHITE=\033[1;37m
ORANGE=\033[38;5;214m
PURPLE=\033[38;5;129m
GRAY=\033[38;5;245m
NC=\033[0m

# === Targets ===
.PHONY: help \
		install dev-install uninstall uninstall-dev \
		run lint format fix check lint-changed \
		test clean

# --- Help ---
help:
	@echo "$(WHITE)🚀 $(PROJECT) Development Toolkit$(NC)"
	@echo
	@echo "$(ORANGE)■ Environment$(NC)"
	@printf "  $(GREEN)install$(NC)%-9s Install base dependencies\n" ""
	@printf "  $(GREEN)install-dev$(NC)%-5s Install base + dev tools\n" ""
	@printf "  $(RED)uninstall$(NC)%-7s Remove virtual environments\n" ""
	@echo
	@echo "$(ORANGE)■ Development$(NC)"
	@printf "  $(CYAN)run$(NC)%-13s Run app (src/main.py)\n" ""
	@printf "  $(CYAN)lint$(NC)%-12s Lint all Python files\n" ""
	@printf "  $(CYAN)format$(NC)%-10s Format code\n" ""
	@printf "  $(CYAN)fix$(NC)%-13s Auto-fix issues\n" ""
	@printf "  $(CYAN)check$(NC)%-11s CI checks\n" ""
	@printf "  $(CYAN)lint-changed$(NC)%-4s Lint changed files\n" ""
	@echo
	@echo "$(ORANGE)■ Maintenance$(NC)"
	@printf "  $(MAGENTA)test$(NC)%-12s Run tests\n" ""
	@printf "  $(MAGENTA)clean$(NC)%-11s Clean project caches\n" ""
	@echo
	@echo "$(GRAY)▶ $(WHITE)make install$(GRAY) to start$(NC)"

# --- Setup ---
install:
	@echo "$(GREEN)📦 Installing base dependencies...$(NC)"
	uv sync --no-dev
	@echo "$(GREEN)✅ Base installed.$(NC)"

install-dev:
	@echo "$(GREEN)🔧 Installing dev dependencies...$(NC)"
	uv sync --extra dev
	@echo "$(GREEN)✅ Dev tools ready.$(NC)"

# --- Uninstall ---
uninstall:
	@echo "$(RED)🗑️  Removing virtual environments...$(NC)"
	rm -rf .venv venv env >/dev/null 2>&1 || true
	@echo "$(GREEN)✅ Virtual environments removed.$(NC)"

# --- Run ---
run: run-main

run-main:
	@echo "$(CYAN)🚀 Starting $(PROJECT) in dev mode...$(NC)"
	$(PYTHON) src/main.py

# --- Lint & Format ---
lint:
	@echo "$(CYAN)🔍 Linting all files...$(NC)"
	$(RUFF) check . --output-format=concise

format:
	@echo "$(CYAN)🎨 Formatting code...$(NC)"
	$(RUFF) format .

check:
	@sh -c '\
	echo "$(CYAN)📊 Static analysis (CI mode)...$(NC)"; \
	if $(RUFF) check . --output-format=github && $(RUFF) format . --check; then \
		echo "$(GREEN)✅ All checks passed.$(NC)"; \
	else \
		echo "$(RED)❌ Checks failed.$(NC)" >&2; \
		exit 1; \
	fi'

fix:
	@sh -c '\
	echo "$(YELLOW)⚡ Auto-fixing issues...$(NC)"; \
	if $(RUFF) check . --fix --unsafe-fixes && $(RUFF) format .; then \
		echo "$(GREEN)✨ All fixable issues resolved.$(NC)"; \
	else \
		echo "$(YELLOW)⚠ Some issues require manual fix.$(NC)" >&2; \
		exit 1; \
	fi'

# --- Smart linting ---
lint-changed:
	@echo "$(CYAN)🔍 Linting changed Python files...$(NC)"
	@CHANGED=""; \
	if git rev-parse --git-dir > /dev/null 2>&1; then \
		if git diff --cached --quiet 2>/dev/null; then \
			if git log -1 > /dev/null 2>&1; then \
				CHANGED=$$(git diff --name-only HEAD~1 2>/dev/null | grep '\.py$$'); \
			else \
				CHANGED=$$(git ls-files '*.py'); \
			fi; \
		else \
			CHANGED=$$(git diff --name-only --cached 2>/dev/null | grep '\.py$$'); \
		fi; \
	else \
		echo "$(YELLOW)⚠ Not a git repo — linting all .py files.$(NC)"; \
		CHANGED=$$(find . -name '*.py' -not -path './.venv/*' -not -path './.git/*'); \
	fi; \
	if [ -z "$$CHANGED" ]; then \
		echo "$(YELLOW)ℹ No Python files to lint.$(NC)"; \
	else \
		echo "$$CHANGED" | xargs $(RUFF) check --output-format=concise; \
	fi

# --- Test (placeholder) ---
test:
	@echo "$(MAGENTA)🧪 Running tests... (add pytest later)$(NC)"
	@echo "$(GRAY)Hint:$(NC) Add 'pytest' to dev dependencies and update this target."

# --- Clean ---
clean:
	@echo "$(MAGENTA)🧹 Cleaning caches...$(NC)"
	@echo "$(GRAY)Cleaning Python caches...$(NC)"
	find . -type d \( \
		-name "__pycache__" -o \
		-name ".mypy_cache" -o \
		-name ".pytest_cache" -o \
		-name ".ruff_cache" \
	\) -prune -exec rm -rf {} + 2>/dev/null || true
	find . -type f \( \
		-name "*.py[co]" -o \
		-name ".coverage" -o \
		-name ".coverage.*" -o \
		-name "coverage.*" \
	\) -delete 2>/dev/null || true
	@echo "$(GREEN)✅ Clean complete.$(NC)"

# --- Variables ---
# DOCKER_DIR := docker
# DEV_PROJECT := cli-logger_dev
# PROD_PROJECT := cli-logger

# BASE_COMPOSE := $(DOCKER_DIR)/docker-compose.yml
# DEV_COMPOSE := $(DOCKER_DIR)/docker-compose.dev.yml

# --- Dev ---
# dev up-dev:
# 	docker compose -f $(BASE_COMPOSE) -f $(DEV_COMPOSE) -p $(DEV_PROJECT) up --build -d --wait --wait-timeout 240

# down-dev:
# 	docker compose -f $(BASE_COMPOSE) -f $(DEV_COMPOSE) -p $(DEV_PROJECT) down --remove-orphans -v

# status-dev:
# 	docker compose -f $(BASE_COMPOSE) -f $(DEV_COMPOSE) -p $(DEV_PROJECT) ps

# logs-dev:
# 	docker compose -f $(BASE_COMPOSE) -f $(DEV_COMPOSE) -p $(DEV_PROJECT) logs -f app

# --- Utilities ---
# app-bash:
# 	docker compose -f $(BASE_COMPOSE) -f $(DEV_COMPOSE) -p $(DEV_PROJECT) exec app bash

# db-shell:
# 	docker compose -f $(BASE_COMPOSE) -f $(DEV_COMPOSE) -p $(DEV_PROJECT) exec db mysql -u root -prootpass

# # --- Prod ---
# prod up-prod:
# 	docker compose -f $(BASE_COMPOSE) -p $(PROD_PROJECT) up --build -d --wait --wait-timeout 60

# down-prod:
# 	docker compose -f $(BASE_COMPOSE) -p $(PROD_PROJECT) down --remove-orphans -v

# status-prod:
# 	docker compose -f $(BASE_COMPOSE) -p $(PROD_PROJECT) ps

# logs-prod:
# 	docker compose -f $(BASE_COMPOSE) -p $(PROD_PROJECT) logs -f app
