# =========================================================
# Project: database-module
# Focused Docker Makefile — only project-specific commands
# =========================================================

PROJECT ?= database-module

# ---------------------------------------------------------
# Tools
# ---------------------------------------------------------

DOCKER := docker

# ---------------------------------------------------------
# Docker Compose — isolated via .env files
# ---------------------------------------------------------

COMPOSE_BASE := -f docker/docker-compose.yml
COMPOSE_DEV  := -f docker/docker-compose.dev.yml
COMPOSE_PROD := -f docker/docker-compose.prod.yml

DC_DEV  := $(DOCKER) compose --env-file .env.dev
DC_PROD := $(DOCKER) compose --env-file .env.prod

# ---------------------------------------------------------
# Secrets
# ---------------------------------------------------------

SECRETS_DIR := docker/secrets
DB_SECRET   := $(SECRETS_DIR)/db_password.txt

# ---------------------------------------------------------
# Colors
# ---------------------------------------------------------

GREEN  := \033[0;32m
RED    := \033[0;31m
BLUE   := \033[0;34m
CYAN   := \033[0;36m
MAGENTA:= \033[0;35m
YELLOW := \033[1;33m
NC     := \033[0m

# ---------------------------------------------------------
.PHONY: help \
	docker-generate-secrets docker-build \
	docker-up-dev docker-down-dev docker-clean-dev docker-clean-volumes-dev \
	docker-up-prod docker-down-prod docker-clean-prod docker-clean-volumes-prod \
	docker-clean-all docker-clean-volumes-all \
	docker-logs-dev docker-logs-prod \
	docker-shell-dev docker-shell-prod \
	docker-ps-dev docker-ps-prod docker-ps-all \
	docker-stats-dev docker-stats-prod docker-stats-all \
	docker-df

# =========================================================
# Help
# =========================================================

help:
	@echo "$(GREEN)🚀 $(PROJECT) — Docker Toolkit$(NC)"
	@echo ""
	@echo "$(CYAN)■ Setup$(NC)"
	@echo "  $(GREEN)docker-generate-secrets$(NC)   Generate secrets"
	@echo "  $(GREEN)docker-build$(NC)             Build app image"
	@echo ""
	@echo "$(CYAN)■ Development$(NC)"
	@echo "  $(BLUE)docker-up-dev$(NC)            Start"
	@echo "  $(RED)docker-down-dev$(NC)           Stop"
	@echo "  $(MAGENTA)docker-clean-dev$(NC)      Stop + remove containers & volumes"
	@echo "  $(MAGENTA)docker-clean-volumes-dev$(NC)  Remove ONLY volumes (safe)"
	@echo ""
	@echo "$(CYAN)■ Production$(NC)"
	@echo "  $(BLUE)docker-up-prod$(NC)           Start"
	@echo "  $(RED)docker-down-prod$(NC)          Stop"
	@echo "  $(MAGENTA)docker-clean-prod$(NC)     Stop + remove containers & volumes"
	@echo "  $(MAGENTA)docker-clean-volumes-prod$(NC) Remove ONLY volumes (safe)"
	@echo ""
	@echo "$(CYAN)■ Global$(NC)"
	@echo "  $(MAGENTA)docker-clean-all$(NC)       Clean BOTH"
	@echo "  $(MAGENTA)docker-clean-volumes-all$(NC)  Remove ALL project volumes"
	@echo ""
	@echo "$(CYAN)■ Logs & Shell$(NC)"
	@echo "  $(CYAN)docker-logs-dev$(NC)          Follow dev logs"
	@echo "  $(CYAN)docker-logs-prod$(NC)         Follow prod logs"
	@echo "  $(BLUE)docker-shell-dev$(NC)         Shell in dev app"
	@echo "  $(BLUE)docker-shell-prod$(NC)        Shell in prod app"
	@echo ""
	@echo "$(CYAN)■ Monitoring$(NC)"
	@echo "  $(CYAN)docker-ps-dev$(NC)            List dev containers"
	@echo "  $(CYAN)docker-ps-prod$(NC)           List prod containers"
	@echo "  $(CYAN)docker-ps-all$(NC)            List all project containers"
	@echo "  $(CYAN)docker-stats-dev$(NC)         Resource usage (dev)"
	@echo "  $(CYAN)docker-stats-prod$(NC)        Resource usage (prod)"
	@echo "  $(CYAN)docker-stats-all$(NC)         Resource usage (all)"
	@echo "  $(CYAN)docker-df$(NC)                Disk usage (project volumes)"

# =========================================================
# Docker — Secrets
# =========================================================

docker-generate-secrets:
	@echo "$(GREEN)🔑 Generating secrets...$(NC)"
	@mkdir -p $(SECRETS_DIR)
	@if [ ! -f "$(DB_SECRET)" ]; then \
		openssl rand -base64 32 > "$(DB_SECRET)"; \
		echo "$(GREEN)✅ DB secret generated$(NC)"; \
	else \
		echo "$(YELLOW)✓ DB secret exists$(NC)"; \
	fi
	@chmod 600 $(SECRETS_DIR)/*.txt 2>/dev/null || true

# =========================================================
# Docker — Build
# =========================================================

docker-build:
	@echo "$(CYAN)🏗️ Building app image...$(NC)"
	@$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) build --quiet app

# =========================================================
# Docker — Development Stack
# =========================================================

docker-up-dev: docker-generate-secrets
	@echo "$(BLUE)🚀 Starting DEV stack...$(NC)"
	@$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) --profile dev up -d --quiet-pull

docker-down-dev:
	@echo "$(RED)🛑 Stopping DEV stack...$(NC)"
	@$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) --profile dev down

docker-clean-dev: docker-down-dev
	@echo "$(MAGENTA)🧹 Removing DEV containers and volumes...$(NC)"
	@$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) --profile dev down -v --remove-orphans

docker-clean-volumes-dev:
	@echo "$(MAGENTA)🧹 Removing ONLY DEV volumes (if stopped)...$(NC)"
	@PROJECT_NAME=database-module-dev; \
	RUNNING_CONTAINERS=$$($(DOCKER) ps -q --filter "name=$$PROJECT_NAME"); \
	if [ -n "$$RUNNING_CONTAINERS" ]; then \
		echo "$(RED)❌ DEV containers are still running — stop first with 'make docker-down-dev'.$(NC)"; \
		echo "Running containers: $$RUNNING_CONTAINERS"; \
		exit 1; \
	fi; \
	VOLUMES_REMOVED=0; \
	for volume in "$$PROJECT_NAME_pgdata" "$$PROJECT_NAME_pgadmin_data"; do \
		if $(DOCKER) volume ls -q --filter name=^$$volume$$ | grep -q .; then \
			if $(DOCKER) volume rm -f "$$volume" 2>/dev/null; then \
				echo "$(GREEN)✅ Removed volume: $$volume$(NC)"; \
				VOLUMES_REMOVED=$$((VOLUMES_REMOVED + 1)); \
			else \
				echo "$(YELLOW)⚠ Could not remove volume (might be in use): $$volume$(NC)"; \
			fi; \
		fi; \
	done; \
	if [ $$VOLUMES_REMOVED -eq 0 ]; then \
		echo "$(YELLOW)⚠ No DEV volumes found to remove or volumes are still referenced.$(NC)"; \
		echo "Use 'docker volume ls' to see all volumes."; \
	fi

# =========================================================
# Docker — Production Stack
# =========================================================

docker-up-prod: docker-generate-secrets docker-build
	@echo "$(BLUE)🏭 Starting PROD stack...$(NC)"
	@$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) --profile prod up -d --quiet-pull

docker-down-prod:
	@echo "$(RED)🛑 Stopping PROD stack...$(NC)"
	@$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) --profile prod down

docker-clean-prod: docker-down-prod
	@echo "$(MAGENTA)🧹 Removing PROD containers and volumes...$(NC)"
	@$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) --profile prod down -v --remove-orphans

docker-clean-volumes-prod:
	@echo "$(MAGENTA)🧹 Removing ONLY PROD volumes (if stopped)...$(NC)"
	@PROJECT=$$($(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) config 2>/dev/null | grep '^name:' | sed 's/name:[[:space:]]*//' | tr -d '\r'); \
	if [ -z "$$PROJECT" ]; then \
		echo "$(RED)❌ Could not determine PROD project name.$(NC)"; exit 1; \
	fi; \
	if $(DOCKER) ps -q --filter label=com.docker.compose.project=$$PROJECT | grep -q .; then \
		echo "$(RED)❌ PROD containers are still running — stop first with 'make docker-down-prod'.$(NC)"; exit 1; \
	fi; \
	$(DOCKER) volume rm -f "$$PROJECT_pgdata" "$$PROJECT_pgadmin_data" 2>/dev/null && \
		echo "$(GREEN)✅ PROD volumes removed: $$PROJECT_pgdata, $$PROJECT_pgadmin_data$(NC)" || \
		echo "$(YELLOW)⚠ No PROD volumes found to remove.$(NC)"

# =========================================================
# Docker — Global Cleanup
# =========================================================

docker-clean-all: docker-clean-dev docker-clean-prod
	@echo "$(GREEN)✅ Both DEV and PROD cleaned.$(NC)"

docker-clean-volumes-all: docker-clean-volumes-dev docker-clean-volumes-prod
	@echo "$(GREEN)✅ All project volumes removed.$(NC)"

# =========================================================
# Docker — Logs & Shell
# =========================================================

docker-check-ports:
	@echo "$(CYAN)🔍 Checking used ports...$(NC)"
	@echo "$(YELLOW)Port 8080 (dev pgadmin):$(NC)" && sudo lsof -i :8080 2>/dev/null || echo "  ✅ Free"
	@echo "$(YELLOW)Port 8081 (prod pgadmin):$(NC)" && sudo lsof -i :8081 2>/dev/null || echo "  ✅ Free"

docker-logs-dev:
	@$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) logs -f

docker-logs-prod:
	@$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) logs -f

docker-shell-dev:
	@$(DC_DEV) $(COMPOSE_BASE) exec app sh

docker-shell-prod:
	@$(DC_PROD) $(COMPOSE_BASE) exec app sh

# =========================================================
# Docker — Monitoring (project-only)
# =========================================================

docker-ps-dev:
	@$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) ps --all

docker-ps-prod:
	@$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) ps --all

docker-ps-all:
	@echo "$(CYAN)📊 DEV:$(NC)"
	@$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) ps --all 2>/dev/null || echo "$(GRAY)No DEV stack.$(NC)"
	@echo ""
	@echo "$(CYAN)📊 PROD:$(NC)"
	@$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) ps --all 2>/dev/null || echo "$(GRAY)No PROD stack.$(NC)"

docker-stats-dev:
	@IDS=$$($(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) ps -q 2>/dev/null); \
	if [ -z "$$IDS" ]; then \
		echo "$(GRAY)No running DEV containers.$(NC)"; \
	else \
		$(DOCKER) stats --no-stream $$IDS; \
	fi

docker-stats-prod:
	@IDS=$$($(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) ps -q 2>/dev/null); \
	if [ -z "$$IDS" ]; then \
		echo "$(GRAY)No running PROD containers.$(NC)"; \
	else \
		$(DOCKER) stats --no-stream $$IDS; \
	fi

docker-stats-all:
	@IDS="$$( \
		$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) ps -q 2>/dev/null; \
		$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) ps -q 2>/dev/null \
	)"; \
	if [ -z "$$IDS" ]; then \
		echo "$(GRAY)No running project containers.$(NC)"; \
	else \
		$(DOCKER) stats --no-stream $$IDS; \
	fi

docker-df:
	@echo "$(CYAN)📦 Project volumes:$(NC)"
	@$(DOCKER) volume ls --filter name=database-module
	@echo ""
	@echo "$(CYAN)📊 Docker disk usage:$(NC)"
	@$(DOCKER) system df
