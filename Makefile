# =========================================================
# Makefile with Active Environment System
# =========================================================

PROJECT ?= my-awesome-app

# ---------------------------------------------------------
# Tools
# ---------------------------------------------------------

DOCKER := docker
SHELL := /bin/bash

# ---------------------------------------------------------
# Environment System
# ---------------------------------------------------------

ACTIVE_ENV_FILE := .active-env
ENV_FILES := .env.dev .env.prod

# Validate files exist
$(foreach env_file,$(ENV_FILES),\
	$(if $(wildcard $(env_file)),,\
		$(warning Environment file $(env_file) not found. Create it from template)))

# Get active environment (default: dev)
CURRENT_ENV := $(strip $(shell if [ -f "$(ACTIVE_ENV_FILE)" ]; then cat "$(ACTIVE_ENV_FILE)" 2>/dev/null; else echo "dev"; fi))

# Validate env
VALID_ENVS := dev prod
ifneq ($(filter $(CURRENT_ENV),$(VALID_ENVS)),)
	ENV_FILE := .env.$(CURRENT_ENV)
	COMPOSE_PROJECT_NAME := $(strip $(shell \
		if [ -f "$(ENV_FILE)" ]; then \
			grep -E '^COMPOSE_PROJECT_NAME=' "$(ENV_FILE)" 2>/dev/null | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'; \
		fi \
	))
endif

ifeq ($(COMPOSE_PROJECT_NAME),)
	COMPOSE_PROJECT_NAME := $(PROJECT)-$(CURRENT_ENV)
endif

# ---------------------------------------------------------
# Docker Compose
# ---------------------------------------------------------

COMPOSE_BASE := -f docker/docker-compose.yml
COMPOSE_OVERRIDE := -f docker/docker-compose.$(CURRENT_ENV).yml
DC := $(DOCKER) compose --env-file $(ENV_FILE)

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
GRAY   := \033[0;90m
NC     := \033[0m

# ---------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------

define get_env_value
	$(strip $(shell \
		if [ -f "$(ENV_FILE)" ]; then \
			grep -E "^$(1)=" "$(ENV_FILE)" 2>/dev/null | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'; \
		fi \
	))
endef

define save_active_env
	@printf '%b' "$(GREEN)✓ Active environment set to: $(1)$(NC)\n"
	@echo "$(1)" > "$(ACTIVE_ENV_FILE)"
endef

define show_env_info
	@printf '%b' "$(CYAN)📦 Current environment: $(GREEN)$(CURRENT_ENV)$(NC)\n"
	@printf '%b' "$(CYAN)📁 Configuration file: $(GRAY)$(ENV_FILE)$(NC)\n"
	@printf '%b' "$(CYAN)🏷️  Project name: $(GRAY)$(COMPOSE_PROJECT_NAME)$(NC)\n"
	@if [ -f "$(ENV_FILE)" ]; then \
		PGPORT=$$(grep -E '^PGADMIN_PORT=' "$(ENV_FILE)" 2>/dev/null | cut -d'=' -f2- || echo 'not specified'); \
		printf '%b' "$(CYAN)📍 PGAdmin port: $(GRAY)$$PGPORT$(NC)\n"; \
		PGIMAGE=$$(grep -E '^PGADMIN_IMAGE=' "$(ENV_FILE)" 2>/dev/null | cut -d'=' -f2- || echo 'dpage/pgadmin4:8.12'); \
		printf '%b' "$(CYAN)🖼️  PGAdmin image: $(GRAY)$$PGIMAGE$(NC)\n"; \
		DBIMAGE=$$(grep -E '^POSTGRES_IMAGE=' "$(ENV_FILE)" 2>/dev/null | cut -d'=' -f2- || echo 'postgres:18.1-bookworm'); \
		printf '%b' "$(CYAN)🗄️  Postgres image: $(GRAY)$$DBIMAGE$(NC)\n"; \
	else \
		printf '%b' "$(RED)⚠ Environment file not found: $(ENV_FILE)$(NC)\n"; \
	fi
endef

define check_resource_existence
	@RESOURCE_EXISTS=$$( $(DOCKER) $(1) "$(2)" > /dev/null 2>&1 && echo "1" || echo "0" ); \
	if [ "$$RESOURCE_EXISTS" -eq 1 ]; then \
		$(3); \
	else \
		$(4); \
	fi
endef

define remove_resource
	@printf '%b' "$(MAGENTA)🧹 Removing $(1) for project: $(2)$(NC)\n"
	@REMOVED=0; \
	for resource in $$($(DOCKER) $(3) --filter "name=^$(2)" --format "{{.$(4)}}" 2>/dev/null); do \
		if $(DOCKER) $(5) "$$resource" > /dev/null 2>&1; then \
			printf '%b' "  $(GREEN)✅ Removed: $$resource$(NC)\n"; \
			REMOVED=$$((REMOVED + 1)); \
		else \
			printf '%b' "  $(YELLOW)⚠ Could not remove: $$resource$(NC)\n"; \
		fi; \
	done; \
	if [ $$REMOVED -eq 0 ]; then \
		printf '%b' "  $(GRAY)ℹ No $(1) found for $(2)$(NC)\n"; \
	fi
endef

define remove_project_volumes
	$(call remove_resource,volumes,$(1),volume ls -q,Name,volume rm -f)
endef

define remove_project_images
	@printf '%b' "$(RED)🔥 Removing images for $(1)...$(NC)\n"
	@IMAGES_REMOVED=0; \
	APP_IMAGE=$(1)-app:latest; \
	if $(DOCKER) image inspect "$$APP_IMAGE" > /dev/null 2>&1; then \
		if $(DOCKER) rmi -f "$$APP_IMAGE" > /dev/null 2>&1; then \
			printf '%b' "  $(GREEN)✅ Removed: $$APP_IMAGE$(NC)\n"; \
			IMAGES_REMOVED=$$((IMAGES_REMOVED + 1)); \
		else \
			printf '%b' "  $(YELLOW)⚠ Could not remove: $$APP_IMAGE$(NC)\n"; \
		fi; \
	else \
		printf '%b' "  $(GRAY)ℹ App image not found: $$APP_IMAGE$(NC)\n"; \
	fi; \
	PGADMIN_IMAGE=$$(grep -E '^PGADMIN_IMAGE=' "$(ENV_FILE)" 2>/dev/null | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
	if [ -n "$$PGADMIN_IMAGE" ]; then \
		if $(DOCKER) image inspect "$$PGADMIN_IMAGE" > /dev/null 2>&1; then \
			if $(DOCKER) rmi -f "$$PGADMIN_IMAGE" > /dev/null 2>&1; then \
				printf '%b' "  $(GREEN)✅ Removed: $$PGADMIN_IMAGE$(NC)\n"; \
				IMAGES_REMOVED=$$((IMAGES_REMOVED + 1)); \
			else \
				printf '%b' "  $(YELLOW)⚠ Could not remove: $$PGADMIN_IMAGE$(NC)\n"; \
			fi; \
		else \
			printf '%b' "  $(GRAY)ℹ PgAdmin image not found: $$PGADMIN_IMAGE$(NC)\n"; \
		fi; \
	else \
		printf '%b' "  $(YELLOW)⚠ PgAdmin image not specified in $(ENV_FILE)$(NC)\n"; \
	fi; \
	POSTGRES_IMAGE=$$(grep -E '^POSTGRES_IMAGE=' "$(ENV_FILE)" 2>/dev/null | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$$//'); \
	if [ -n "$$POSTGRES_IMAGE" ]; then \
		if $(DOCKER) image inspect "$$POSTGRES_IMAGE" > /dev/null 2>&1; then \
			if $(DOCKER) rmi -f "$$POSTGRES_IMAGE" > /dev/null 2>&1; then \
				printf '%b' "  $(GREEN)✅ Removed: $$POSTGRES_IMAGE$(NC)\n"; \
				IMAGES_REMOVED=$$((IMAGES_REMOVED + 1)); \
			else \
				printf '%b' "  $(YELLOW)⚠ Could not remove: $$POSTGRES_IMAGE$(NC)\n"; \
			fi; \
		else \
			printf '%b' "  $(GRAY)ℹ Postgres image not found: $$POSTGRES_IMAGE$(NC)\n"; \
		fi; \
	else \
		printf '%b' "  $(YELLOW)⚠ Postgres image not specified in $(ENV_FILE)$(NC)\n"; \
	fi; \
	DANGLING=$$($(DOCKER) images --filter "dangling=true" -q 2>/dev/null); \
	if [ -n "$$DANGLING" ]; then \
		printf '%b' "  $(BLUE)🧹 Pruning dangling layers...$(NC)\n"; \
		if $(DOCKER) image prune -f > /dev/null 2>&1; then \
			printf '%b' "  $(GREEN)✅ Pruned dangling layers$(NC)\n"; \
			IMAGES_REMOVED=$$((IMAGES_REMOVED + 1)); \
		fi; \
	fi; \
	if [ $$IMAGES_REMOVED -eq 0 ]; then \
		printf '%b' "  $(GRAY)ℹ No images to remove$(NC)\n"; \
	fi
endef

define clean_project_build_cache
	@printf '%b' "$(MAGENTA)🧹 Cleaning build cache for $(1)...$(NC)\n"
	@if $(DOCKER) builder prune --filter label=com.docker.compose.project=$(1) -f > /dev/null 2>&1; then \
		printf '%b' "  $(GREEN)✅ Build cache pruned$(NC)\n"; \
	else \
		printf '%b' "  $(GRAY)ℹ No build cache to remove$(NC)\n"; \
	fi
endef

define check_containers_for_volumes
	@ALL_CONTAINERS=$$($(DOCKER) ps -aq --filter "name=$(1)" 2>/dev/null); \
	if [ -n "$$ALL_CONTAINERS" ]; then \
		RUNNING=$$($(DOCKER) ps -q --filter "name=$(1)" --filter "status=running" 2>/dev/null); \
		if [ -n "$$RUNNING" ]; then \
			RUNNING_LIST=$$(echo "$$RUNNING" | tr '\n' ' ' | sed 's/ *$$//'); \
			RUNNING_NAMES=$$($(DOCKER) ps --format "{{.Names}}" --filter "id=$$RUNNING_LIST" 2>/dev/null | tr '\n' ' '); \
			printf '%b' "$(RED)❌ $(1) containers are still RUNNING: $$RUNNING_NAMES$(NC)\n"; \
			printf '%b' "  → Stop them first: $(YELLOW)make stop$(NC)\n"; \
			exit 1; \
		else \
			printf '%b' "$(YELLOW)⚠ $(1) containers exist but are STOPPED.$(NC)\n"; \
			printf '%b' "  → Remove them first: $(GREEN)make clean$(NC)\n"; \
			exit 1; \
		fi; \
	fi
endef

# ---------------------------------------------------------
# Targets
# ---------------------------------------------------------

.PHONY: help \
	env env-dev env-prod env-status \
	test-env-files check-secrets \
	up down stop build clean clean-volumes clean-images clean-networks clean-build-cache clean-all \
	logs logs-pgadmin logs-db logs-app shell ps stats \
	ports check-ports df disk \
	nuke \
	generate-secrets

default: env-status

# =========================================================
# Environment
# =========================================================

env-status:
	$(call show_env_info)

env-dev:
	$(call save_active_env,dev)

env-prod:
	$(call save_active_env,prod)

env:
	@printf '%b' "$(CYAN)🔄 Switching environment$(NC)\n"
	@printf '%b' "Current environment: $(GREEN)$(CURRENT_ENV)$(NC)\n\n"
	@printf '%b' "Select environment:\n"
	@printf '%b' "  1) $(GREEN)dev$(NC)    - Development\n"
	@printf '%b' "  2) $(RED)prod$(NC)   - Production\n\n"
	@printf '%b' "$(YELLOW)Choice [1-2] (Enter=keep current): $(NC)"
	@read -r choice; \
	if [ "$$choice" = "1" ] || [ "$$choice" = "dev" ]; then \
		echo "Switched to: dev" && echo "dev" > "$(ACTIVE_ENV_FILE)"; \
	elif [ "$$choice" = "2" ] || [ "$$choice" = "prod" ]; then \
		echo "Switched to: prod" && echo "prod" > "$(ACTIVE_ENV_FILE)"; \
	elif [ -z "$$choice" ]; then \
		echo "Keeping current environment: $(CURRENT_ENV)"; \
	else \
		echo "❌ Invalid choice. Enter 1, 2, or press Enter to keep current."; \
	fi
	@if [ -f "$(ACTIVE_ENV_FILE)" ]; then \
		NEW_ENV=$$(cat "$(ACTIVE_ENV_FILE)"); \
		if [ "$$NEW_ENV" != "$(CURRENT_ENV)" ]; then \
			printf '%b' "$(GREEN)✓ Active environment set to: $$NEW_ENV$(NC)\n"; \
		fi; \
	fi

# Проверка файлов окружения
test-env-files:
	@if [ ! -f ".env.dev" ]; then \
		printf '%b' "$(RED)❌ Missing .env.dev$(NC)\n"; \
		printf '%b' "  Copy from example: cp .env.example .env.dev\n"; \
		exit 1; \
	fi
	@if [ ! -f ".env.prod" ]; then \
		printf '%b' "$(RED)❌ Missing .env.prod$(NC)\n"; \
		printf '%b' "  Copy from example: cp .env.example .env.prod\n"; \
		exit 1; \
	fi
	@printf '%b' "$(GREEN)✓ All environment files present$(NC)\n"

# =========================================================
# Docker Operations
# =========================================================

generate-secrets:
	@printf '%b' "$(GREEN)🔑 Checking secrets for $(CURRENT_ENV) environment...$(NC)\n"
	@mkdir -p "$(SECRETS_DIR)" 2>/dev/null || true
	@SECRETS_CREATED=0; \
	if [ ! -f "$(DB_SECRET)" ]; then \
		openssl rand -base64 32 > "$(DB_SECRET)"; \
		printf '%b' "  $(GREEN)✅ Database secret generated$(NC)\n"; \
		SECRETS_CREATED=1; \
	else \
		printf '%b' "  $(YELLOW)✓ Database secret already exists$(NC)\n"; \
	fi; \
	if [ ! -f "$(SECRETS_DIR)/pgadmin_password.txt" ]; then \
		openssl rand -base64 32 > "$(SECRETS_DIR)/pgadmin_password.txt"; \
		printf '%b' "  $(GREEN)✅ PgAdmin secret generated$(NC)\n"; \
		SECRETS_CREATED=1; \
	else \
		printf '%b' "  $(YELLOW)✓ PgAdmin secret already exists$(NC)\n"; \
	fi; \
	chmod 600 "$(SECRETS_DIR)"/*.txt 2>/dev/null || true; \
	if [ $$SECRETS_CREATED -eq 0 ]; then \
		printf '%b' "$(GREEN)✓ All secrets already exist$(NC)\n"; \
	fi

# Проверка секретов
check-secrets:
	@printf '%b' "$(CYAN)🔍 Checking secrets...$(NC)\n"
	@if [ ! -d "$(SECRETS_DIR)" ]; then \
		printf '%b' "$(RED)❌ Secrets directory not found: $(SECRETS_DIR)$(NC)\n"; \
		exit 1; \
	fi; \
	MISSING=0; \
	if [ ! -f "$(DB_SECRET)" ]; then \
		printf '%b' "$(RED)❌ Missing: db_password.txt$(NC)\n"; \
		MISSING=1; \
	fi; \
	if [ ! -f "$(SECRETS_DIR)/pgadmin_password.txt" ]; then \
		printf '%b' "$(RED)❌ Missing: pgadmin_password.txt$(NC)\n"; \
		MISSING=1; \
	fi; \
	if [ $$MISSING -eq 0 ]; then \
		printf '%b' "$(GREEN)✓ All secrets present$(NC)\n"; \
	else \
		printf '%b' "$(YELLOW)Run 'make generate-secrets' to create missing files$(NC)\n"; \
		exit 1; \
	fi

build: test-env-files
	@printf '%b' "$(CYAN)🏗️ Building application image for $(CURRENT_ENV) environment...$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) build --quiet app 2>/dev/null || \
	$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) build --quiet app

up: test-env-files check-secrets
	@printf '%b' "$(BLUE)🚀 Starting stack for $(CURRENT_ENV) environment...$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) --profile "$(CURRENT_ENV)" up -d > /dev/null 2>&1
	@printf '%b' "$(GREEN)✅ Stack started$(NC)\n"
	@printf '\n'
	$(call show_env_info)
	@printf '\n'
	@printf '%b' "$(YELLOW)📊 Container status:$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) ps --all 2>/dev/null | tail -n +2

stop:
	@printf '%b' "$(YELLOW)⏸️ Stopping containers for $(CURRENT_ENV) environment...$(NC)\n"
	@CONTAINERS=$$($(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) ps -q 2>/dev/null); \
	if [ -z "$$CONTAINERS" ]; then \
		printf '%b' "  $(GRAY)ℹ No running containers to stop$(NC)\n"; \
	else \
		for container in $$CONTAINERS; do \
			NAME=$$($(DOCKER) ps --format "{{.Names}}" --filter "id=$$container" 2>/dev/null); \
			printf '%b' "  $(YELLOW)⏸️ Stopping: $$NAME$(NC)\n"; \
		done; \
		printf '\n'; \
		$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) --profile "$(CURRENT_ENV)" stop; \
		printf '%b' "\n  $(GREEN)✅ Containers stopped$(NC)\n"; \
	fi

down:
	@printf '%b' "$(RED)🛑 Stopping and removing containers & networks$(NC)\n"
	@printf '%b' "$(GRAY)Step 1: Stopping containers...$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) --profile "$(CURRENT_ENV)" stop
	@printf '%b' "$(GRAY)Step 2: Removing containers and networks...$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) --profile "$(CURRENT_ENV)" down
	@printf '%b' "$(GREEN)✅ Containers and networks removed$(NC)\n"

clean: down
	@printf '%b' "\n$(MAGENTA)🧹 Clean completed: containers & networks removed$(NC)\n"

clean-volumes:
	$(call check_containers_for_volumes,$(COMPOSE_PROJECT_NAME))
	$(call remove_project_volumes,$(COMPOSE_PROJECT_NAME))

clean-images:
	$(call check_containers_for_volumes,$(COMPOSE_PROJECT_NAME))
	$(call remove_project_images,$(COMPOSE_PROJECT_NAME))

clean-networks:
	$(call remove_resource,networks,$(COMPOSE_PROJECT_NAME),network ls -q,Name,network rm)

clean-build-cache:
	$(call clean_project_build_cache,$(COMPOSE_PROJECT_NAME))

clean-all: clean-volumes clean-images clean-networks clean-build-cache
	@printf '%b' "$(GREEN)✅ All project resources cleaned (except containers)$(NC)\n"

# =========================================================
# Logs & Shell
# =========================================================

logs:
	@printf '%b' "$(CYAN)📋 Logs for $(CURRENT_ENV) environment:$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) logs -f --tail=100 2>/dev/null

logs-pgadmin:
	@printf '%b' "$(CYAN)📋 PgAdmin logs for $(CURRENT_ENV) environment:$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) logs -f --tail=100 pgadmin 2>/dev/null

logs-db:
	@printf '%b' "$(CYAN)📋 Database logs for $(CURRENT_ENV) environment:$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) logs -f --tail=100 db 2>/dev/null

logs-app:
	@printf '%b' "$(CYAN)📋 App logs for $(CURRENT_ENV) environment:$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) logs -f --tail=100 app 2>/dev/null

shell:
	@printf '%b' "$(BLUE)🐚 Connecting to app container ($(CURRENT_ENV))...$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) exec app sh 2>/dev/null

# =========================================================
# Monitoring
# =========================================================

ps:
	@printf '%b' "$(CYAN)📊 Containers for $(CURRENT_ENV) environment:$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) ps --all 2>/dev/null || \
	printf '%b' "$(YELLOW)⚠ No containers found$(NC)\n"

stats:
	@printf '%b' "$(CYAN)📈 Resource usage for $(CURRENT_ENV):$(NC)\n"
	@IDS=$$($(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) ps -q 2>/dev/null); \
	if [ -z "$$IDS" ]; then \
		printf '%b' "$(YELLOW)⚠ No running containers$(NC)\n"; \
	else \
		$(DOCKER) stats --no-stream $$IDS 2>/dev/null || true; \
	fi

ports:
	@printf '%b' "$(CYAN)🌐 Port mapping for $(COMPOSE_PROJECT_NAME):$(NC)\n"
	@CONTAINERS=$$($(DOCKER) ps --format "{{.Names}}" --filter "name=$(COMPOSE_PROJECT_NAME)" 2>/dev/null); \
	if [ -z "$$CONTAINERS" ]; then \
		printf '%b' "  $(YELLOW)⚠ No running containers$(NC)\n"; \
	else \
		for c in $$CONTAINERS; do \
			printf '%b' "  📦 $$c\n"; \
			PORTS=$$($(DOCKER) port "$$c" 2>/dev/null); \
			if [ -n "$$PORTS" ]; then \
				echo "$$PORTS" | while IFS= read -r p; do \
					[ -n "$$p" ] && printf '    %s\n' "$$p"; \
				done; \
			else \
				printf '%b' "    $(GRAY)No exposed ports$(NC)\n"; \
			fi; \
		done; \
	fi

check-ports:
	@printf '%b' "$(CYAN)🔍 Checking port availability...$(NC)\n"
	@PGPORT=$$(grep -E '^PGADMIN_PORT=' "$(ENV_FILE)" 2>/dev/null | cut -d'=' -f2- || echo "8080"); \
	printf '%b' "$(GRAY) • PGAdmin:$(NC) $$PGPORT → "; \
	if command -v ss >/dev/null 2>&1; then \
		ss -tln | grep -q ":$$PGPORT " && printf '%b' "$(RED)BUSY$(NC)\n" || printf '%b' "$(GREEN)FREE$(NC)\n"; \
	elif command -v netstat >/dev/null 2>&1; then \
		netstat -tln | grep -q ":$$PGPORT " && printf '%b' "$(RED)BUSY$(NC)\n" || printf '%b' "$(GREEN)FREE$(NC)\n"; \
	else \
		printf '%b' "$(YELLOW)UNKNOWN$(NC)\n"; \
	fi
	@printf '%b' "$(GRAY) • PostgreSQL:$(NC) 5432 → "; \
	if command -v ss >/dev/null 2>&1; then \
		ss -tln | grep -q ":5432 " && printf '%b' "$(RED)BUSY$(NC)\n" || printf '%b' "$(GREEN)FREE$(NC)\n"; \
	elif command -v netstat >/dev/null 2>&1; then \
		netstat -tln | grep -q ":5432 " && printf '%b' "$(RED)BUSY$(NC)\n" || printf '%b' "$(GREEN)FREE$(NC)\n"; \
	else \
		printf '%b' "$(YELLOW)UNKNOWN$(NC)\n"; \
	fi

df:
	@printf '%b' "$(CYAN)📊 Docker disk usage:$(NC)\n"
	@$(DOCKER) system df 2>/dev/null || true

disk:
	@printf '%b' "$(CYAN)💾 Detailed disk usage:$(NC)\n"
	@$(DOCKER) system df --verbose 2>/dev/null || true

# =========================================================
# NUKE — Complete destruction
# =========================================================

nuke:
	@printf '%b' "$(RED)💣 COMPLETE DESTRUCTION for $(CURRENT_ENV) environment$(NC)\n"
	@printf '%b' "$(YELLOW)This will remove:$(NC)\n"
	@printf '  • Containers and networks\n'
	@printf '  • Project volumes\n'
	@printf '  • Project images\n'
	@printf '  • Build cache\n'
	@printf '\n'
	@printf '%b' "$(YELLOW)Are you sure? [y/N]: $(NC)"; \
	read -r confirm; \
	if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
		printf '%b' "$(YELLOW)Cancelled$(NC)\n"; \
		exit 0; \
	fi
	@printf '\n'

	@printf '%b' "$(MAGENTA)1️⃣  Stopping and removing containers and networks$(NC)\n"
	@printf '%b' "$(GRAY)  Stopping containers...$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) --profile "$(CURRENT_ENV)" stop > /dev/null 2>&1 || true
	@printf '%b' "$(GRAY)  Removing containers and networks...$(NC)\n"
	@$(DC) $(COMPOSE_BASE) $(COMPOSE_OVERRIDE) --profile "$(CURRENT_ENV)" down > /dev/null 2>&1 || true
	@printf '%b' "$(GREEN)  ✅ Containers and networks removed$(NC)\n"

	@printf '%b' "$(MAGENTA)2️⃣  Removing volumes$(NC)\n"
	$(call remove_project_volumes,$(COMPOSE_PROJECT_NAME))

	@printf '%b' "$(MAGENTA)3️⃣  Removing images$(NC)\n"
	$(call remove_project_images,$(COMPOSE_PROJECT_NAME))

	@printf '%b' "$(MAGENTA)4️⃣  Cleaning build cache$(NC)\n"
	$(call clean_project_build_cache,$(COMPOSE_PROJECT_NAME))

	@printf '\n'
	@printf '%b' "$(GREEN)✅ $(CURRENT_ENV) environment fully destroyed$(NC)\n"

# =========================================================
# Help
# =========================================================

help:
	@printf '%b' "$(GREEN)🚀 $(PROJECT) — Docker Control$(NC)\n"
	@printf '\n'
	@printf '%b' "$(CYAN)📦 Active environment: $(GREEN)$(CURRENT_ENV)$(NC)\n"
	@printf '\n'
	@printf '%b' "$(CYAN)■ Environment$(NC)\n"
	@printf '  env env-dev env-prod env-status test-env-files check-secrets\n'
	@printf '\n'
	@printf '%b' "$(CYAN)■ Lifecycle$(NC)\n"
	@printf '  up down stop build clean\n'
	@printf '\n'
	@printf '%b' "$(CYAN)■ Cleanup$(NC)\n"
	@printf '  clean-volumes clean-images clean-networks clean-build-cache clean-all nuke\n'
	@printf '\n'
	@printf '%b' "$(CYAN)■ Debug$(NC)\n"
	@printf '  logs logs-pgadmin logs-db logs-app shell ps stats ports check-ports df disk\n'
	@printf '\n'
	@printf '%b' "$(CYAN)■ Secrets$(NC)\n"
	@printf '  generate-secrets\n'
	@printf '\n'
	@printf '%b' "$(GRAY)ℹ Active env stored in: $(ACTIVE_ENV_FILE)$(NC)\n"
