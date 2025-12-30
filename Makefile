# =========================================================
# Makefile
# =========================================================

PROJECT ?= my-awesome-app

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
GRAY   := \033[0;90m
NC     := \033[0m

# ---------------------------------------------------------
# Helper functions
# ---------------------------------------------------------

# Function to remove project volumes
define remove_project_volumes
	@echo "$(MAGENTA)🧹 Removing volumes for project: $(1)$(NC)"; \
	VOLUMES_REMOVED=0; \
	for volume in $$($(DOCKER) volume ls -q --filter name=^$(1) 2>/dev/null); do \
		if $(DOCKER) volume rm -f "$$volume" 2>/dev/null; then \
			echo "  $(GREEN)✅ Removed: $$volume$(NC)"; \
			VOLUMES_REMOVED=$$((VOLUMES_REMOVED + 1)); \
		else \
			echo "  $(YELLOW)⚠ Could not remove (might be in use): $$volume$(NC)"; \
		fi; \
	done; \
	if [ $$VOLUMES_REMOVED -eq 0 ]; then \
		echo "$(YELLOW)⚠ No volumes found for project: $(1)$(NC)"; \
	fi
endef

# Function to check if containers are running
define check_running_containers
	@RUNNING_CONTAINERS=$$($(DOCKER) ps -q --filter "name=$(1)" 2>/dev/null); \
	if [ -n "$$RUNNING_CONTAINERS" ]; then \
		echo "$(RED)❌ $(1) containers are still running!$(NC)"; \
		echo "  Running containers: $$RUNNING_CONTAINERS"; \
		echo "  Stop first with: make docker-down-$(2)"; \
		exit 1; \
	fi
endef

# Function to get project port mapping
define get_project_ports
	@echo "$(CYAN)🌐 Ports for project: $(1)$(NC)"; \
	CONTAINERS=$$($(DOCKER) ps --format "{{.Names}}" --filter "name=$(1)" 2>/dev/null); \
	if [ -z "$$CONTAINERS" ]; then \
		echo "  $(YELLOW)No running containers$(NC)"; \
	else \
		for container in $$CONTAINERS; do \
			echo "  Container: $$container"; \
			PORTS=$$($(DOCKER) port "$$container" 2>/dev/null); \
			if [ -n "$$PORTS" ]; then \
				echo "$$PORTS" | while read line; do \
					[ -n "$$line" ] && echo "    $$line"; \
				done; \
			else \
				echo "    $(GRAY)No exposed ports$(NC)"; \
			fi; \
		done; \
	fi
endef

# Function to clean project build cache
define clean_project_build_cache
	@echo "$(MAGENTA)🧹 Cleaning build cache for $(1)...$(NC)"; \
	$(DOCKER) builder prune --filter label=com.docker.compose.project=$(1) -f > /dev/null 2>&1 || true
endef

# Function to remove ALL images for a project
define remove_all_project_images
	@echo "$(RED)🔥 Removing ALL images for $(1)...$(NC)"; \
	# Remove app image \
	echo "  Removing app image: $(1)-app:latest"; \
	$(DOCKER) rmi -f "$(1)-app:latest" 2>/dev/null || echo "    $(YELLOW)App image not found$(NC)"; \
	# Remove pgadmin if not used elsewhere \
	PGADMIN_USERS=$$($(DOCKER) ps -a --filter ancestor=dpage/pgadmin4:latest --format "{{.Names}}" 2>/dev/null | grep -c . || echo "0"); \
	if [ "$$PGADMIN_USERS" -le 1 ]; then \
		echo "  Removing pgadmin image"; \
		$(DOCKER) rmi -f dpage/pgadmin4:latest 2>/dev/null || echo "    $(YELLOW)PgAdmin image not found or in use$(NC)"; \
	else \
		echo "  $(YELLOW)⚠ pgadmin image is used by $$PGADMIN_USERS container(s)$(NC)"; \
	fi; \
	# Remove postgres if not used elsewhere \
	POSTGRES_USERS=$$($(DOCKER) ps -a --filter ancestor=postgres:18.1-bookworm --format "{{.Names}}" 2>/dev/null | grep -c . || echo "0"); \
	if [ "$$POSTGRES_USERS" -le 1 ]; then \
		echo "  Removing postgres image"; \
		$(DOCKER) rmi -f postgres:18.1-bookworm 2>/dev/null || echo "    $(YELLOW)Postgres image not found or in use$(NC)"; \
	else \
		echo "  $(YELLOW)⚠ postgres image is used by $$POSTGRES_USERS container(s)$(NC)"; \
	fi
endef

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
	docker-df docker-disk docker-disk-project \
	docker-check-ports docker-ports-dev docker-ports-prod docker-ports-all \
	docker-rmi-dev docker-rmi-prod docker-rmi-all \
	docker-clean-images-dev docker-clean-images-prod docker-clean-images-all \
	docker-nuke-dev docker-nuke-prod docker-nuke-all

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
	@echo "  $(BLUE)docker-up-dev$(NC)            Start stack"
	@echo "  $(RED)docker-down-dev$(NC)           Stop stack"
	@echo "  $(MAGENTA)docker-clean-dev$(NC)      Stop + remove containers & volumes"
	@echo "  $(MAGENTA)docker-clean-volumes-dev$(NC)  Remove ONLY volumes"
	@echo "  $(RED)docker-nuke-dev$(NC)           NUKE: Remove EVERYTHING (images too!)"
	@echo ""
	@echo "$(CYAN)■ Production$(NC)"
	@echo "  $(BLUE)docker-up-prod$(NC)           Start stack"
	@echo "  $(RED)docker-down-prod$(NC)          Stop stack"
	@echo "  $(MAGENTA)docker-clean-prod$(NC)     Stop + remove containers & volumes"
	@echo "  $(MAGENTA)docker-clean-volumes-prod$(NC) Remove ONLY volumes"
	@echo "  $(RED)docker-nuke-prod$(NC)          NUKE: Remove EVERYTHING (images too!)"
	@echo ""
	@echo "$(CYAN)■ Global Cleanup$(NC)"
	@echo "  $(MAGENTA)docker-clean-all$(NC)       Clean BOTH stacks"
	@echo "  $(MAGENTA)docker-clean-volumes-all$(NC)  Remove ALL project volumes"
	@echo "  $(MAGENTA)docker-clean-images-dev$(NC) Remove DEV images (app only)"
	@echo "  $(MAGENTA)docker-clean-images-prod$(NC) Remove PROD images (app only)"
	@echo "  $(MAGENTA)docker-clean-images-all$(NC)  Remove ALL project app images"
	@echo "  $(RED)docker-nuke-all$(NC)           NUKE ALL: Remove EVERYTHING for both envs"
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
	@echo "  $(CYAN)docker-df$(NC)                Docker disk usage"
	@echo "  $(CYAN)docker-disk$(NC)              Detailed disk usage"
	@echo "  $(CYAN)docker-disk-project$(NC)      Project-specific disk usage"
	@echo ""
	@echo "$(CYAN)■ Network & Ports$(NC)"
	@echo "  $(CYAN)docker-check-ports$(NC)       Check used ports"
	@echo "  $(CYAN)docker-ports-dev$(NC)         Show DEV port mapping"
	@echo "  $(CYAN)docker-ports-prod$(NC)        Show PROD port mapping"
	@echo "  $(CYAN)docker-ports-all$(NC)         Show ALL port mappings"

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
	@if [ ! -f "$(SECRETS_DIR)/pgadmin_password.txt" ]; then \
		openssl rand -base64 32 > "$(SECRETS_DIR)/pgadmin_password.txt"; \
		echo "$(GREEN)✅ PgAdmin secret generated$(NC)"; \
	else \
		echo "$(YELLOW)✓ PgAdmin secret exists$(NC)"; \
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
	$(call check_running_containers,database-module-dev,dev)
	$(call remove_project_volumes,database-module-dev)

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
	$(call check_running_containers,database-module-prod,prod)
	$(call remove_project_volumes,database-module-prod)

# =========================================================
# Docker — Global Cleanup
# =========================================================

docker-clean-all: docker-clean-dev docker-clean-prod
	@echo "$(GREEN)✅ Both DEV and PROD cleaned.$(NC)"

docker-clean-volumes-all: docker-clean-volumes-dev docker-clean-volumes-prod
	@echo "$(GREEN)✅ All project volumes removed.$(NC)"

# =========================================================
# Docker — Image Management (APP ONLY)
# =========================================================

docker-rmi-dev:
	$(call check_running_containers,database-module-dev,dev)
	@echo "$(MAGENTA)🗑️ Removing DEV app image...$(NC)"
	@if $(DOCKER) rmi -f database-module-dev-app:latest 2>/dev/null; then \
		echo "$(GREEN)✅ DEV app image removed$(NC)"; \
	else \
		echo "$(YELLOW)⚠ DEV app image not found$(NC)"; \
	fi

docker-rmi-prod:
	$(call check_running_containers,database-module-prod,prod)
	@echo "$(MAGENTA)🗑️ Removing PROD app image...$(NC)"
	@if $(DOCKER) rmi -f database-module-prod-app:latest 2>/dev/null; then \
		echo "$(GREEN)✅ PROD app image removed$(NC)"; \
	else \
		echo "$(YELLOW)⚠ PROD app image not found$(NC)"; \
	fi

docker-rmi-all: docker-rmi-dev docker-rmi-prod
	@echo "$(GREEN)✅ All project app images removed.$(NC)"

docker-clean-images-dev: docker-rmi-dev
	$(call clean_project_build_cache,database-module-dev)

docker-clean-images-prod: docker-rmi-prod
	$(call clean_project_build_cache,database-module-prod)

docker-clean-images-all: docker-clean-images-dev docker-clean-images-prod
	@echo "$(GREEN)✅ All project images and caches removed.$(NC)"

# =========================================================
# Docker — NUKE Commands (COMPLETE DESTRUCTION)
# =========================================================

docker-nuke-dev:
	@echo "$(RED)💣 NUKE: Removing EVERYTHING for DEV...$(NC)"
	@echo "$(YELLOW)This will remove:$(NC)"
	@echo "  - DEV containers"
	@echo "  - DEV volumes"
	@echo "  - DEV app image"
	@echo "  - pgadmin image (if only used by DEV)"
	@echo "  - postgres image (if only used by DEV)"
	@echo ""
	@printf "$(YELLOW)Are you sure? [y/N]: $(NC)"; \
	read confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		echo "$(RED)Stopping DEV containers...$(NC)"; \
		-$(DC_DEV) down 2>/dev/null || true; \
		$(call remove_project_volumes,database-module-dev); \
		$(call remove_all_project_images,database-module-dev); \
		$(call clean_project_build_cache,database-module-dev); \
		echo "$(GREEN)✅ DEV environment NUKED.$(NC)"; \
	else \
		echo "$(YELLOW)Nuke cancelled.$(NC)"; \
	fi

docker-nuke-prod:
	@echo "$(RED)💣 NUKE: Removing EVERYTHING for PROD...$(NC)"
	@echo "$(YELLOW)This will remove:$(NC)"
	@echo "  - PROD containers"
	@echo "  - PROD volumes"
	@echo "  - PROD app image"
	@echo "  - pgadmin image (if only used by PROD)"
	@echo "  - postgres image (if only used by PROD)"
	@echo ""
	@printf "$(YELLOW)Are you sure? [y/N]: $(NC)"; \
	read confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		echo "$(RED)Stopping PROD containers...$(NC)"; \
		-$(DC_PROD) down 2>/dev/null || true; \
		$(call remove_project_volumes,database-module-prod); \
		$(call remove_all_project_images,database-module-prod); \
		$(call clean_project_build_cache,database-module-prod); \
		echo "$(GREEN)✅ PROD environment NUKED.$(NC)"; \
	else \
		echo "$(YELLOW)Nuke cancelled.$(NC)"; \
	fi

docker-nuke-all:
	@echo "$(RED)💣💣 NUKE ALL: Removing EVERYTHING for both environments$(NC)"
	@echo "$(YELLOW)This will remove:$(NC)"
	@echo "  - ALL containers (DEV & PROD)"
	@echo "  - ALL volumes (DEV & PROD)"
	@echo "  - ALL images (app, pgadmin, postgres)"
	@echo "  - ALL build cache"
	@echo ""
	@echo "$(RED)WARNING: This cannot be undone!$(NC)"
	@echo ""
	@printf "$(YELLOW)Type 'NUKE' to confirm: $(NC)"; \
	read confirm; \
	if [ "$$confirm" = "NUKE" ]; then \
		echo "$(RED)Initiating complete nuke...$(NC)"; \
		echo "$(RED)Stopping all containers...$(NC)"; \
		-$(DC_DEV) down 2>/dev/null || true; \
		-$(DC_PROD) down 2>/dev/null || true; \
		echo "$(RED)Removing all volumes...$(NC)"; \
		$(call remove_project_volumes,database-module-dev); \
		$(call remove_project_volumes,database-module-prod); \
		echo "$(RED)Removing ALL images...$(NC)"; \
		$(DOCKER) rmi -f database-module-dev-app:latest 2>/dev/null || true; \
		$(DOCKER) rmi -f database-module-prod-app:latest 2>/dev/null || true; \
		$(DOCKER) rmi -f dpage/pgadmin4:latest 2>/dev/null || true; \
		$(DOCKER) rmi -f postgres:18.1-bookworm 2>/dev/null || true; \
		echo "$(RED)Cleaning all build cache...$(NC)"; \
		$(DOCKER) builder prune -a -f > /dev/null 2>&1 || true; \
		$(DOCKER) system prune -f > /dev/null 2>&1 || true; \
		echo "$(GREEN)✅✅ COMPLETE NUKED. System is clean.$(NC)"; \
	else \
		echo "$(YELLOW)Nuke cancelled.$(NC)"; \
	fi

# =========================================================
# Docker — Logs & Shell
# =========================================================

docker-logs-dev:
	@$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) logs -f

docker-logs-prod:
	@$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) logs -f

docker-shell-dev:
	@$(DC_DEV) $(COMPOSE_BASE) exec app sh

docker-shell-prod:
	@$(DC_PROD) $(COMPOSE_BASE) exec app sh

# =========================================================
# Docker — Monitoring
# =========================================================

docker-ps-dev:
	@$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) ps --all

docker-ps-prod:
	@$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) ps --all

docker-ps-all:
	@echo "$(CYAN)📊 DEV:$(NC)"
	@$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) ps --all 2>/dev/null || echo "$(YELLOW)No DEV stack.$(NC)"
	@echo ""
	@echo "$(CYAN)📊 PROD:$(NC)"
	@$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) ps --all 2>/dev/null || echo "$(YELLOW)No PROD stack.$(NC)"

docker-stats-dev:
	@IDS=$$($(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) ps -q 2>/dev/null); \
	if [ -z "$$IDS" ]; then \
		echo "$(YELLOW)No running DEV containers.$(NC)"; \
	else \
		$(DOCKER) stats --no-stream $$IDS; \
	fi

docker-stats-prod:
	@IDS=$$($(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) ps -q 2>/dev/null); \
	if [ -z "$$IDS" ]; then \
		echo "$(YELLOW)No running PROD containers.$(NC)"; \
	else \
		$(DOCKER) stats --no-stream $$IDS; \
	fi

docker-stats-all:
	@IDS="$$( \
		$(DC_DEV) $(COMPOSE_BASE) $(COMPOSE_DEV) ps -q 2>/dev/null; \
		$(DC_PROD) $(COMPOSE_BASE) $(COMPOSE_PROD) ps -q 2>/dev/null \
	)"; \
	if [ -z "$$IDS" ]; then \
		echo "$(YELLOW)No running project containers.$(NC)"; \
	else \
		$(DOCKER) stats --no-stream $$IDS; \
	fi

docker-df:
	@echo "$(CYAN)📊 Docker disk usage:$(NC)"
	@$(DOCKER) system df

docker-disk:
	@echo "$(CYAN)💾 Detailed Docker disk usage:$(NC)"
	@$(DOCKER) system df --verbose

docker-disk-project:
	@echo "$(CYAN)💾 Project-specific disk usage:$(NC)"
	@echo "$(YELLOW)Images:$(NC)"
	@$(DOCKER) images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" --filter "reference=database-module*" 2>/dev/null || echo "  $(YELLOW)No project images$(NC)"
	@echo ""
	@echo "$(YELLOW)Volumes:$(NC)"
	@$(DOCKER) volume ls --format "table {{.Name}}\t{{.Driver}}\t{{.Mountpoint}}" --filter "name=database-module" 2>/dev/null || echo "  $(YELLOW)No project volumes$(NC)"
	@echo ""
	@echo "$(YELLOW)Containers (all statuses):$(NC)"
	@$(DOCKER) ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}" --filter "name=database-module" 2>/dev/null || echo "  $(YELLOW)No project containers$(NC)"

# =========================================================
# Docker — Network & Ports
# =========================================================

docker-check-ports:
	@echo "$(CYAN)🔍 Checking used ports...$(NC)"
	@echo "$(YELLOW)Project ports:$(NC)"
	@echo "  Port 8080 (dev pgadmin):" && (sudo lsof -i :8080 2>/dev/null | head -5 || echo "    $(GREEN)✅ Free$(NC)")
	@echo "  Port 8081 (prod pgadmin):" && (sudo lsof -i :8081 2>/dev/null | head -5 || echo "    $(GREEN)✅ Free$(NC)")
	@echo "  Port 5432 (postgres):" && (sudo lsof -i :5432 2>/dev/null | head -5 || echo "    $(GREEN)✅ Free$(NC)")
	@echo ""
	@echo "$(YELLOW)All Docker container ports:$(NC)"
	@$(DOCKER) ps --format "table {{.Names}}\t{{.Ports}}" | grep -E "(8080|8081|5432|80|443)" 2>/dev/null || echo "  $(YELLOW)No relevant ports$(NC)"

docker-ports-dev:
	$(call get_project_ports,database-module-dev)

docker-ports-prod:
	$(call get_project_ports,database-module-prod)

docker-ports-all:
	@echo "$(CYAN)🌐 All project port mappings:$(NC)"
	@echo ""
	$(call get_project_ports,database-module-dev)
	@echo ""
	$(call get_project_ports,database-module-prod)
