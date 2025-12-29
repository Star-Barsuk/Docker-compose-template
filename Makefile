# =========================================================
# Project configuration
# =========================================================

PROJECT ?= database-module

# ---------------------------------------------------------
# Tools
# ---------------------------------------------------------

PYTHON := uv run python
RUFF   := uv run ruff
DC     := docker compose

# ---------------------------------------------------------
# Docker compose files
# ---------------------------------------------------------

COMPOSE_BASE := -f docker/docker-compose.yml
COMPOSE_DEV  := -f docker/docker-compose.dev.yml
COMPOSE_PROD := -f docker/docker-compose.prod.yml

# ---------------------------------------------------------
# Secrets
# ---------------------------------------------------------

SECRETS_DIR      := docker/secrets
DB_SECRET        := $(SECRETS_DIR)/db_password.txt
PGADMIN_SECRET   := $(SECRETS_DIR)/pgadmin_password.txt

# ---------------------------------------------------------
# Colors
# ---------------------------------------------------------

RED     := \033[0;31m
GREEN   := \033[0;32m
YELLOW  := \033[1;33m
BLUE    := \033[0;34m
MAGENTA := \033[0;35m
CYAN    := \033[0;36m
GRAY    := \033[38;5;245m
WHITE   := \033[1;37m
ORANGE  := \033[38;5;214m
NC      := \033[0m

# ---------------------------------------------------------
# Meta
# ---------------------------------------------------------

.DEFAULT_GOAL := help

.PHONY: help \
        install install-dev uninstall run \
        lint format fix check lint-changed test clean \
        docker-generate-secrets docker-build \
        docker-up-dev docker-up-prod docker-down docker-clean \
        docker-logs docker-log-app docker-log-db docker-log-pgadmin \
        docker-shell docker-python docker-exec \
        docker-ps docker-stats docker-prune

# =========================================================
# Help
# =========================================================

help:
	@echo "$(WHITE)🚀 $(PROJECT) — Development Toolkit$(NC)"
	@echo
	@echo "$(ORANGE)■ Environment$(NC)"
	@printf "  $(GREEN)install$(NC)%-18s Install core dependencies\n" ""
	@printf "  $(GREEN)install-dev$(NC)%-14s Install dev dependencies\n" ""
	@printf "  $(RED)uninstall$(NC)%-16s Remove virtual environments\n" ""
	@echo
	@echo "$(ORANGE)■ Development$(NC)"
	@printf "  $(CYAN)run$(NC)%-22s Run app locally\n" ""
	@printf "  $(CYAN)lint$(NC)%-21s Lint code\n" ""
	@printf "  $(CYAN)format$(NC)%-19s Format code\n" ""
	@printf "  $(CYAN)fix$(NC)%-22s Auto-fix lint issues\n" ""
	@printf "  $(CYAN)check$(NC)%-20s Lint + format (CI)\n" ""
	@printf "  $(CYAN)lint-changed$(NC)%-12s Lint changed files only\n" ""
	@echo
	@echo "$(ORANGE)■ Docker$(NC)"
	@printf "  $(BLUE)docker-up-dev$(NC)%-15s Start dev stack\n" ""
	@printf "  $(BLUE)docker-up-prod$(NC)%-14s Start prod stack\n" ""
	@printf "  $(BLUE)docker-down$(NC)%-17s Stop all containers\n" ""
	@printf "  $(BLUE)docker-clean$(NC)%-16s Stop and remove volumes\n" ""
	@printf "  $(BLUE)docker-logs$(NC)%-18s Follow logs\n" ""
	@printf "  $(BLUE)docker-shell$(NC)%-15s Open shell in app container\n" ""
	@printf "  $(BLUE)docker-exec cmd='…'$(NC)%-6s Run command in container\n" ""
	@printf "  $(BLUE)docker-ps$(NC)%-21s Show container status\n" ""
	@printf "  $(BLUE)docker-stats$(NC)%-18s Show resource usage\n" ""
	@echo
	@echo "$(GRAY)▶ make install-dev • make docker-up-dev$(NC)"

# =========================================================
# Python / Environment
# =========================================================

install:
	@echo "$(GREEN)📦 Installing core dependencies...$(NC)"
	uv sync --no-dev
	@echo "$(GREEN)✅ Core dependencies installed.$(NC)"

install-dev:
	@echo "$(GREEN)🔧 Installing development dependencies...$(NC)"
	uv sync --extra dev
	@echo "$(GREEN)✅ Development environment ready.$(NC)"

uninstall:
	@echo "$(RED)🗑️ Removing virtual environments...$(NC)"
	rm -rf .venv venv env
	@echo "$(GREEN)✅ Virtual environments removed.$(NC)"

run:
	@echo "$(CYAN)🚀 Starting application...$(NC)"
	$(PYTHON) -m app

# =========================================================
# Lint & Format
# =========================================================

lint:
	@echo "$(CYAN)🔍 Linting code...$(NC)"
	$(RUFF) check .

format:
	@echo "$(CYAN)🎨 Formatting code...$(NC)"
	$(RUFF) format .

check:
	@echo "$(CYAN)📊 Running CI checks...$(NC)"
	$(RUFF) check . --output-format=github
	$(RUFF) format . --check
	@echo "$(GREEN)✅ All checks passed.$(NC)"

fix:
	@echo "$(YELLOW)⚡ Auto-fixing issues...$(NC)"
	$(RUFF) check . --fix --unsafe-fixes
	$(RUFF) format .
	@echo "$(GREEN)✨ Fixable issues resolved.$(NC)"

lint-changed:
	@echo "$(CYAN)🔍 Linting changed Python files...$(NC)"
	@set -e; \
	FILES="$$(git diff --name-only --diff-filter=ACM | grep '\.py$$' || true)"; \
	if [ -z "$$FILES" ]; then \
		echo "$(GRAY)ℹ No Python files changed.$(NC)"; \
	else \
		echo "$$FILES" | xargs $(RUFF) check; \
	fi

test:
	@echo "$(MAGENTA)🧪 Tests not configured yet.$(NC)"

clean:
	@echo "$(MAGENTA)🧹 Cleaning Python caches...$(NC)"
	find . -type d \( -name "__pycache__" -o -name ".ruff_cache" \) -exec rm -rf {} +
	@echo "$(GREEN)✅ Cleanup complete.$(NC)"

# =========================================================
# Docker — Secrets
# =========================================================

docker-generate-secrets:
	@echo "$(GREEN)🔑 Ensuring secrets exist...$(NC)"
	@mkdir -p $(SECRETS_DIR)
	@test -f $(DB_SECRET) || openssl rand -base64 32 > $(DB_SECRET)
	@test -f $(PGADMIN_SECRET) || openssl rand -base64 32 > $(PGADMIN_SECRET)
	@chmod 600 $(SECRETS_DIR)/*.txt
	@echo "$(GREEN)✅ Secrets ready.$(NC)"

# =========================================================
# Docker — Build & Lifecycle
# =========================================================

docker-build:
	@echo "$(CYAN)🏗️ Building application image...$(NC)"
	$(DC) $(COMPOSE_BASE) build app

docker-up-db: docker-generate-secrets
	@echo "$(CYAN)🗄️ Starting database only...$(NC)"
	$(DC) --profile db $(COMPOSE_BASE) up -d

docker-up-dev: docker-generate-secrets
	@echo "$(CYAN)🚀 Starting DEV stack...$(NC)"
	$(DC) --profile dev $(COMPOSE_BASE) $(COMPOSE_DEV) up -d

docker-up-prod: docker-generate-secrets docker-build
	@echo "$(CYAN)🏭 Starting PROD stack...$(NC)"
	$(DC) --profile prod $(COMPOSE_BASE) $(COMPOSE_PROD) up -d

docker-down:
	@echo "$(RED)🛑 Stopping all containers...$(NC)"
	$(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) $(COMPOSE_PROD) down

docker-clean:
	@echo "$(MAGENTA)🧹 Removing containers and volumes...$(NC)"
	$(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) $(COMPOSE_PROD) down -v --remove-orphans

# =========================================================
# Docker — Logs & Exec
# =========================================================

docker-logs:
	$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) logs -f

docker-log-app:
	$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) logs -f app

docker-log-db:
	$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) logs -f db

docker-log-pgadmin:
	$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) logs -f pgadmin

docker-shell:
	@echo "$(BLUE)🐚 Opening shell in app container...$(NC)"
	$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) exec app sh

docker-python:
	@echo "$(BLUE)🐍 Starting Python REPL in container...$(NC)"
	$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) exec app python

docker-exec:
	@test -n "$(cmd)" || (echo "$(RED)Usage: make docker-exec cmd='...'.$(NC)" && exit 1)
	$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) exec app $(cmd)

# =========================================================
# Docker — Info & Maintenance
# =========================================================

docker-ps:
	$(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) $(COMPOSE_PROD) ps

docker-stats:
	@IDS="$$( $(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) $(COMPOSE_PROD) ps -q )"; \
	if [ -z "$$IDS" ]; then \
		echo "$(GRAY)No running containers.$(NC)"; \
	else \
		docker stats $$IDS; \
	fi

docker-prune:
	@echo "$(RED)🗑️ Pruning unused Docker resources...$(NC)"
	docker system prune -a --volumes
