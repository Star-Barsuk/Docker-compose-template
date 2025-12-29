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
DOCKER := docker

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

RED     := \033[0;31m    	# Errors, destructive operations
GREEN   := \033[0;32m    	# Success, completion
YELLOW  := \033[1;33m    	# Warnings, confirmations
BLUE    := \033[0;34m    	# Information, status
MAGENTA := \033[0;35m    	# Cleanup operations
CYAN    := \033[0;36m    	# Actions, commands
WHITE   := \033[1;37m    	# Headers, titles
ORANGE  := \033[38;5;214m	# Important notices
GRAY    := \033[38;5;245m	# Subtle info, metadata
NC      := \033[0m

# ---------------------------------------------------------
# Meta
# ---------------------------------------------------------

.DEFAULT_GOAL := help

.PHONY: help \
        install install-dev uninstall run \
        lint format fix check lint-changed test clean \
        docker-generate-secrets docker-build \
        docker-up-db docker-down-db \
        docker-up-dev docker-down-dev docker-clean-dev \
        docker-up-prod docker-down-prod docker-clean-prod \
        docker-down-all docker-clean-all \
        docker-logs docker-log-app docker-log-db docker-log-pgadmin \
        docker-shell docker-python docker-exec \
        docker-ps docker-stats docker-df \
        docker-prune docker-prune-containers docker-prune-images \
        docker-prune-volumes docker-prune-networks docker-prune-build-cache \
        docker-prune-all docker-system-clean

# =========================================================
# Help
# =========================================================

help:
	@echo "$(WHITE)🚀 $(PROJECT) — Development Toolkit$(NC)"
	@echo "$(GRAY)════════════════════════════════════════════$(NC)"
	@echo ""
	@echo "$(ORANGE)■ Environment$(NC)"
	@printf "  $(GREEN)install$(NC)%-21s Install core dependencies only\n" ""
	@printf "  $(GREEN)install-dev$(NC)%-17s Install all dependencies (including dev)\n" ""
	@printf "  $(RED)uninstall$(NC)%-19s Remove virtual environments\n" ""
	@printf "  $(CYAN)run$(NC)%-25s Run app locally (without Docker)\n" ""
	@echo ""
	@echo "$(ORANGE)■ Code Quality$(NC)"
	@printf "  $(CYAN)lint$(NC)%-24s Check code with ruff\n" ""
	@printf "  $(CYAN)format$(NC)%-22s Format code\n" ""
	@printf "  $(CYAN)fix$(NC)%-25s Auto-fix lint issues\n" ""
	@printf "  $(CYAN)check$(NC)%-23s Lint + format check (CI)\n" ""
	@printf "  $(CYAN)lint-changed$(NC)%-16s Lint only changed files\n" ""
	@printf "  $(CYAN)clean$(NC)%-23s Clean Python caches\n" ""
	@echo ""
	@echo "$(ORANGE)■ Docker — Development Stack$(NC)"
	@printf "  $(BLUE)docker-up-dev$(NC)%-15s Start dev stack (app + db + pgadmin)\n" ""
	@printf "  $(RED)docker-down-dev$(NC)%-13s Stop dev stack\n" ""
	@printf "  $(MAGENTA)docker-clean-dev$(NC)%-12s Stop and remove dev volumes\n" ""
	@echo ""
	@echo "$(ORANGE)■ Docker — Production Stack$(NC)"
	@printf "  $(BLUE)docker-up-prod$(NC)%-14s Start prod stack (app + db + pgadmin)\n" ""
	@printf "  $(RED)docker-down-prod$(NC)%-12s Stop prod stack\n" ""
	@printf "  $(MAGENTA)docker-clean-prod$(NC)%-11s Stop and remove prod volumes\n" ""
	@echo ""
	@echo "$(ORANGE)■ Docker — Database Only$(NC)"
	@printf "  $(BLUE)docker-up-db$(NC)%-16s Start only database\n" ""
	@printf "  $(RED)docker-down-db$(NC)%-14s Stop only database\n" ""
	@echo ""
	@echo "$(ORANGE)■ Docker — Build & Secrets$(NC)"
	@printf "  $(BLUE)docker-build$(NC)%-16s Build application image\n" ""
	@printf "  $(GREEN)docker-generate-secrets$(NC)%-5s Generate secrets if missing\n" ""
	@echo ""
	@echo "$(ORANGE)■ Docker — Monitoring & Logs$(NC)"
	@printf "  $(CYAN)docker-logs$(NC)%-17s Follow all logs\n" ""
	@printf "  $(CYAN)docker-log-app$(NC)%-14s Follow app logs\n" ""
	@printf "  $(CYAN)docker-log-db$(NC)%-15s Follow database logs\n" ""
	@printf "  $(CYAN)docker-log-pgadmin$(NC)%-10s Follow pgAdmin logs\n" ""
	@printf "  $(CYAN)docker-ps$(NC)%-19s Show container status\n" ""
	@printf "  $(CYAN)docker-stats$(NC)%-16s Show resource usage\n" ""
	@printf "  $(CYAN)docker-df$(NC)%-19s Show Docker disk usage\n" ""
	@echo ""
	@echo "$(ORANGE)■ Docker — Execution$(NC)"
	@printf "  $(BLUE)docker-shell$(NC)%-16s Open shell in app container\n" ""
	@printf "  $(BLUE)docker-python$(NC)%-15s Start Python REPL in container\n" ""
	@printf "  $(BLUE)docker-exec cmd='…'$(NC)%-9s Run command in container\n" ""
	@echo ""
	@echo "$(ORANGE)■ Docker — Cleanup$(NC)"
	@printf "  $(RED)docker-down-all$(NC)%-13s Stop ALL containers\n" ""
	@printf "  $(MAGENTA)docker-clean-all$(NC)%-12s Stop and remove ALL volumes\n" ""
	@echo ""
	@echo "$(ORANGE)■ Docker — Prune Operations$(NC)"
	@printf "  $(CYAN)docker-prune$(NC)%-16s Interactive prune (safe)\n" ""
	@printf "  $(RED)docker-prune-all$(NC)%-12s Non-interactive aggressive prune\n" ""
	@printf "  $(MAGENTA)docker-system-clean$(NC)%-9s Deep system cleanup\n" ""
	@printf "  $(MAGENTA)docker-prune-containers$(NC)%-5s Remove stopped containers\n" ""
	@printf "  $(MAGENTA)docker-prune-images$(NC)%-9s Remove unused images\n" ""
	@printf "  $(MAGENTA)docker-prune-volumes$(NC)%-8s Remove unused volumes\n" ""
	@printf "  $(MAGENTA)docker-prune-networks$(NC)%-7s Remove unused networks\n" ""
	@printf "  $(MAGENTA)docker-prune-build-cache$(NC)%-4s Remove build cache\n" ""
	@echo ""

# =========================================================
# Python — Environment
# =========================================================

install:
	@echo "$(GREEN)📦 Installing core dependencies...$(NC)"
	@uv sync --no-dev
	@echo "$(GREEN)✅ Core dependencies installed.$(NC)"

install-dev:
	@echo "$(GREEN)🔧 Installing development dependencies...$(NC)"
	@uv sync --extra dev
	@echo "$(GREEN)✅ Development environment ready.$(NC)"

uninstall:
	@echo "$(RED)🗑️ Removing virtual environments...$(NC)"
	@rm -rf .venv venv env
	@echo "$(GREEN)✅ Virtual environments removed.$(NC)"

run:
	@echo "$(CYAN)🚀 Starting application...$(NC)"
	@$(PYTHON) -m app

# =========================================================
# Python — Code Quality
# =========================================================

lint:
	@echo "$(CYAN)🔍 Linting code...$(NC)"
	@$(RUFF) check .

format:
	@echo "$(CYAN)🎨 Formatting code...$(NC)"
	@$(RUFF) format .

check:
	@echo "$(CYAN)📊 Running CI checks...$(NC)"
	@$(RUFF) check . --output-format=github
	@$(RUFF) format . --check
	@echo "$(GREEN)✅ All checks passed.$(NC)"

fix:
	@echo "$(YELLOW)⚡ Auto-fixing issues...$(NC)"
	@$(RUFF) check . --fix --unsafe-fixes
	@$(RUFF) format .
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

clean:
	@echo "$(MAGENTA)🧹 Cleaning Python caches...$(NC)"
	@find . -type d \( -name "__pycache__" -o -name ".ruff_cache" \) -exec rm -rf {} + >/dev/null 2>&1
	@echo "$(GREEN)✅ Cleanup complete.$(NC)"

# =========================================================
# Docker — Secrets
# =========================================================

docker-generate-secrets:
	@echo "$(GREEN)🔑 Managing secrets...$(NC)"
	@mkdir -p $(SECRETS_DIR)
	
	@if [ "$(FORCE)" = "true" ]; then \
		openssl rand -base64 32 > "$(DB_SECRET)"; \
		echo "$(GREEN)✅ DB secret regenerated$(NC)"; \
	elif [ ! -f "$(DB_SECRET)" ]; then \
		openssl rand -base64 32 > "$(DB_SECRET)"; \
		echo "$(GREEN)✅ DB secret generated$(NC)"; \
	else \
		echo "$(GRAY)✓ DB secret already exists (use FORCE=true to regenerate)$(NC)"; \
	fi
	
	@if [ "$(FORCE)" = "true" ]; then \
		openssl rand -base64 32 > "$(PGADMIN_SECRET)"; \
		echo "$(GREEN)✅ pgAdmin secret regenerated$(NC)"; \
	elif [ ! -f "$(PGADMIN_SECRET)" ]; then \
		openssl rand -base64 32 > "$(PGADMIN_SECRET)"; \
		echo "$(GREEN)✅ pgAdmin secret generated$(NC)"; \
	else \
		echo "$(GRAY)✓ pgAdmin secret already exists (use FORCE=true to regenerate)$(NC)"; \
	fi
	
	@chmod 600 $(SECRETS_DIR)/*.txt 2>/dev/null || true

# =========================================================
# Docker — Build
# =========================================================

docker-build:
	@echo "$(CYAN)🏗️ Building application image...$(NC)"
	@$(DC) $(COMPOSE_BASE) build --quiet app

# =========================================================
# Docker — Development Stack
# =========================================================

docker-up-dev: docker-generate-secrets
	@echo "$(CYAN)🚀 Starting DEV stack...$(NC)"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) --profile dev up -d --quiet-pull
	@echo "$(GREEN)✅ DEV stack started.$(NC)"

docker-down-dev:
	@echo "$(RED)🛑 Stopping DEV stack...$(NC)"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) --profile dev down
	@echo "$(GREEN)✅ DEV stack stopped.$(NC)"

docker-clean-dev:
	@echo "$(MAGENTA)🧹 Removing DEV containers and volumes...$(NC)"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) --profile dev down -v --remove-orphans
	@echo "$(GREEN)✅ DEV stack removed.$(NC)"

# =========================================================
# Docker — Production Stack
# =========================================================

docker-up-prod: docker-generate-secrets docker-build
	@echo "$(CYAN)🏭 Starting PROD stack...$(NC)"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) --profile prod up -d --quiet-pull
	@echo "$(GREEN)✅ PROD stack started.$(NC)"

docker-down-prod:
	@echo "$(RED)🛑 Stopping PROD stack...$(NC)"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) --profile prod down
	@echo "$(GREEN)✅ PROD stack stopped.$(NC)"

docker-clean-prod:
	@echo "$(MAGENTA)🧹 Removing PROD containers and volumes...$(NC)"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) --profile prod down -v --remove-orphans
	@echo "$(GREEN)✅ PROD stack removed.$(NC)"

# =========================================================
# Docker — Database Only
# =========================================================

docker-up-db: docker-generate-secrets
	@echo "$(CYAN)🗄️ Starting database only...$(NC)"
	@$(DC) $(COMPOSE_BASE) --profile db up -d --quiet-pull
	@echo "$(GREEN)✅ Database started.$(NC)"

docker-down-db:
	@echo "$(RED)🛑 Stopping database...$(NC)"
	@$(DC) $(COMPOSE_BASE) --profile db down
	@echo "$(GREEN)✅ Database stopped.$(NC)"

# =========================================================
# Docker — Global Operations
# =========================================================

docker-down-all:
	@echo "$(RED)🛑 Stopping ALL containers...$(NC)"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) $(COMPOSE_PROD) down >/dev/null 2>&1 || true
	@echo "$(GREEN)✅ All containers stopped.$(NC)"

docker-clean-all:
	@echo "$(MAGENTA)🧹 Removing ALL containers and volumes...$(NC)"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) $(COMPOSE_PROD) down -v --remove-orphans >/dev/null 2>&1 || true
	@echo "$(GREEN)✅ All containers and volumes removed.$(NC)"

# =========================================================
# Docker — Logs
# =========================================================

docker-logs:
	@echo "$(CYAN)📋 Showing logs for active profile...$(NC)"
	@if [ -f docker/docker-compose.dev.yml ] && [ -n "$$(docker ps -q --filter label=com.docker.compose.project=$${COMPOSE_PROJECT_NAME:-my-awesome-app})" ]; then \
		$(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) logs -f; \
	elif [ -f docker/docker-compose.prod.yml ] && [ -n "$$(docker ps -q --filter label=com.docker.compose.project=$${COMPOSE_PROJECT_NAME:-my-awesome-app})" ]; then \
		$(DC) $(COMPOSE_BASE) $(COMPOSE_PROD) logs -f; \
	else \
		echo "$(GRAY)ℹ No active containers found.$(NC)"; \
	fi

docker-log-app:
	@$(DC) $(COMPOSE_BASE) logs -f app

docker-log-db:
	@$(DC) $(COMPOSE_BASE) logs -f db

docker-log-pgadmin:
	@$(DC) $(COMPOSE_BASE) logs -f pgadmin

# =========================================================
# Docker — Execution
# =========================================================

docker-shell:
	@echo "$(BLUE)🐚 Opening shell in app container...$(NC)"
	@$(DC) $(COMPOSE_BASE) exec app sh

docker-python:
	@echo "$(BLUE)🐍 Starting Python REPL in container...$(NC)"
	@$(DC) $(COMPOSE_BASE) exec app python

docker-exec:
	@test -n "$(cmd)" || (echo "$(RED)Usage: make docker-exec cmd='...'.$(NC)" && exit 1)
	@$(DC) $(COMPOSE_BASE) exec app $(cmd)

# =========================================================
# Docker — Monitoring
# =========================================================

docker-ps:
	@echo "$(CYAN)📊 Container status for all profiles:$(NC)"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) $(COMPOSE_PROD) ps --all

docker-stats:
	@echo "$(CYAN)📈 Resource usage:$(NC)"
	@IDS="$$( $(DC) $(COMPOSE_BASE) $(COMPOSE_DEV) $(COMPOSE_PROD) ps -q )"; \
	if [ -z "$$IDS" ]; then \
		echo "$(GRAY)No running containers.$(NC)"; \
	else \
		docker stats $$IDS; \
	fi

docker-df:
	@echo "$(CYAN)📊 Docker disk usage:$(NC)"
	@docker system df
	@echo ""
	@echo "$(CYAN)📦 Volume usage:$(NC)"
	@docker system df -v

# =========================================================
# Docker — Prune Operations
# =========================================================

docker-prune:
	@echo "$(RED)🗑️ Pruning unused Docker resources...$(NC)"
	@echo "$(YELLOW)This will remove:$(NC)"
	@echo "$(GRAY)  • Stopped containers$(NC)"
	@echo "$(GRAY)  • Unused networks$(NC)"
	@echo "$(GRAY)  • Dangling images$(NC)"
	@echo "$(GRAY)  • Build cache$(NC)"
	@printf "$(YELLOW)Continue? [y/N]: $(NC)"
	@read confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		docker system prune -a --volumes -f >/dev/null 2>&1; \
		echo "$(GREEN)✅ Prune completed.$(NC)"; \
	else \
		echo "$(GRAY)Prune cancelled.$(NC)"; \
	fi

docker-prune-containers:
	@echo "$(RED)🗑️ Pruning stopped containers...$(NC)"
	@CONTAINERS=$$(docker ps -aq -f status=exited); \
	if [ -z "$$CONTAINERS" ]; then \
		echo "$(GRAY)No stopped containers found.$(NC)"; \
	else \
		echo "$(YELLOW)Removing $$(echo "$$CONTAINERS" | wc -l) stopped container(s):$(NC)"; \
		echo "$$CONTAINERS" | xargs -r docker rm -v >/dev/null 2>&1 || true; \
		echo "$(GREEN)✅ Stopped containers removed.$(NC)"; \
	fi

docker-prune-images:
	@echo "$(RED)🗑️ Pruning unused images...$(NC)"
	@IMAGES=$$(docker images -q -f dangling=true); \
	if [ -z "$$IMAGES" ]; then \
		echo "$(GRAY)No dangling images found.$(NC)"; \
	else \
		echo "$(YELLOW)Removing $$(echo "$$IMAGES" | wc -l) dangling image(s):$(NC)"; \
		echo "$$IMAGES" | xargs -r docker rmi >/dev/null 2>&1 || true; \
		echo "$(GREEN)✅ Dangling images removed.$(NC)"; \
	fi
	@echo "$(YELLOW)Removing unused images (not just dangling)...$(NC)"
	@docker image prune -a -f >/dev/null 2>&1
	@echo "$(GREEN)✅ Unused images removed.$(NC)"

docker-prune-volumes:
	@echo "$(RED)🗑️ Pruning unused volumes...$(NC)"
	@echo "$(YELLOW)This will remove volumes not used by any container.$(NC)"
	@echo "$(YELLOW)WARNING: This may remove important data!$(NC)"
	@printf "$(YELLOW)Continue? [y/N]: $(NC)"
	@read confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		docker volume prune -f >/dev/null 2>&1; \
		echo "$(GREEN)✅ Unused volumes removed.$(NC)"; \
	else \
		echo "$(GRAY)Prune cancelled.$(NC)"; \
	fi

docker-prune-networks:
	@echo "$(RED)🗑️ Pruning unused networks...$(NC)"
	@docker network prune -f >/dev/null 2>&1
	@echo "$(GREEN)✅ Unused networks removed.$(NC)"

docker-prune-build-cache:
	@echo "$(RED)🗑️ Pruning build cache...$(NC)"
	@docker builder prune -f >/dev/null 2>&1
	@echo "$(GREEN)✅ Build cache removed.$(NC)"

docker-prune-all:
	@echo "$(RED)🔥 Aggressive pruning of ALL unused resources...$(NC)"
	@echo "$(YELLOW)Removing:$(NC)"
	@echo "$(GRAY)  • All stopped containers$(NC)"
	@echo "$(GRAY)  • All unused networks$(NC)"
	@echo "$(GRAY)  • All unused images (not just dangling)$(NC)"
	@echo "$(GRAY)  • All unused volumes$(NC)"
	@echo "$(GRAY)  • All build cache$(NC)"
	@docker system prune -a --volumes -f >/dev/null 2>&1
	@echo "$(GREEN)✅ All unused resources removed.$(NC)"

docker-system-clean:
	@echo "$(RED)🧹 Deep system cleanup...$(NC)"
	@echo "$(YELLOW)This will:$(NC)"
	@echo "$(GRAY)  1. Remove all stopped containers$(NC)"
	@echo "$(GRAY)  2. Remove all unused networks$(NC)"
	@echo "$(GRAY)  3. Remove all unused images$(NC)"
	@echo "$(GRAY)  4. Remove all unused volumes$(NC)"
	@echo "$(GRAY)  5. Remove all build cache$(NC)"
	@echo "$(GRAY)  6. Remove all unused buildx cache$(NC)"
	@echo ""
	@printf "$(YELLOW)Continue? [y/N]: $(NC)"
	@read confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		echo "$(RED)Starting deep cleanup...$(NC)"; \
		docker system prune -a --volumes -f >/dev/null 2>&1; \
		docker builder prune -a -f >/dev/null 2>&1; \
		echo "$(GREEN)✅ Deep cleanup complete!$(NC)"; \
		echo "$(CYAN)Current disk usage:$(NC)"; \
		docker system df; \
	else \
		echo "$(GRAY)Cleanup cancelled.$(NC)"; \
	fi
