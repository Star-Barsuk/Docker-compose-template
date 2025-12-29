# Makefile

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
        install install-dev uninstall \
        run lint format fix check lint-changed \
        test clean \
        docker-generate-secrets docker-build \
        docker-up-dev docker-up-prod docker-down docker-clean \
        docker-logs docker-log-app docker-log-db docker-log-pgadmin docker-log-tail \
        docker-shell docker-exec docker-bash docker-python \
        docker-ps docker-stats docker-inspect-app \
        docker-prune docker-images docker-volumes

# --- Help ---
help:
	@echo "$(WHITE)🚀 $(PROJECT) Development Toolkit$(NC)"
	@echo
	@echo "$(ORANGE)■ Environment$(NC)"
	@printf " $(GREEN)install$(NC)%-18s Install base dependencies\n" ""
	@printf " $(GREEN)install-dev$(NC)%-13s Install base + dev tools\n" ""
	@printf " $(RED)uninstall$(NC)%-16s Remove virtual environments\n" ""
	@echo
	@echo "$(ORANGE)■ Development$(NC)"
	@printf " $(CYAN)run$(NC)%-22s Run app locally (src/main.py)\n" ""
	@printf " $(CYAN)lint$(NC)%-21s Lint all Python files\n" ""
	@printf " $(CYAN)format$(NC)%-19s Format code\n" ""
	@printf " $(CYAN)fix$(NC)%-22s Auto-fix issues\n" ""
	@printf " $(CYAN)check$(NC)%-20s CI checks (lint + format)\n" ""
	@printf " $(CYAN)lint-changed$(NC)%-12s Lint changed files\n" ""
	@echo
	@echo "$(ORANGE)■ Docker$(NC)"
	@printf " $(BLUE)docker-generate-secrets$(NC)%-4s Generate strong passwords\n" ""
	@printf " $(BLUE)docker-build$(NC)%-14s Build app image\n" ""
	@printf " $(BLUE)docker-up-dev$(NC)%-11s Start dev stack (alpine DB)\n" ""
	@printf " $(BLUE)docker-up-prod$(NC)%-10s Start prod stack (bookworm DB)\n" ""
	@printf " $(BLUE)docker-down$(NC)%-13s Stop all containers\n" ""
	@printf " $(BLUE)docker-clean$(NC)%-12s Stop + remove volumes\n" ""
	@printf " $(BLUE)docker-logs$(NC)%-14s Follow all logs\n" ""
	@printf " $(BLUE)docker-log-app$(NC)%-10s Follow app logs\n" ""
	@printf " $(BLUE)docker-log-db$(NC)%-11s Follow DB logs\n" ""
	@printf " $(BLUE)docker-log-pgadmin$(NC)%-4s Follow pgAdmin logs\n" ""
	@printf " $(BLUE)docker-shell$(NC)%-11s Shell in app container\n" ""
	@printf " $(BLUE)docker-exec cmd='...'%-4s Run command in app\n" ""
	@printf " $(BLUE)docker-ps$(NC)%-17s Show container status\n" ""
	@printf " $(BLUE)docker-stats$(NC)%-14s Live resource usage\n" ""
	@echo
	@echo "$(ORANGE)■ Maintenance$(NC)"
	@printf " $(MAGENTA)test$(NC)%-21s Run tests (placeholder)\n" ""
	@printf " $(MAGENTA)clean$(NC)%-20s Clean Python caches\n" ""
	@printf " $(MAGENTA)docker-prune$(NC)%-12s Prune unused Docker resources\n" ""
	@echo
	@echo "$(GRAY)▶ $(WHITE)make install$(GRAY) to start • $(WHITE)make docker-up-dev$(GRAY) for containers$(NC)"

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
	@echo "$(RED)🗑️ Removing virtual environments...$(NC)"
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

# === Docker Targets ===

# --- Secrets ---
docker-generate-secrets:
	@echo "$(GREEN)🔑 Generating strong random secrets...$(NC)"
	@mkdir -p docker/secrets
	@openssl rand -base64 32 > docker/secrets/db_password.txt
	@openssl rand -base64 32 > docker/secrets/pgadmin_password.txt
	@chmod 600 docker/secrets/*.txt
	@echo "$(GREEN)✅ Secrets created in docker/secrets/ (never commit!)$(NC)"

# --- Build ---
docker-build:
	@echo "$(CYAN)🏗️ Building application image...$(NC)"
	docker compose -f docker/docker-compose.yml build app

# --- Up/Down ---
docker-up-dev:
	@make docker-generate-secrets || true
	@echo "$(CYAN)🚀 Starting development stack (alpine DB, mounted secrets)...$(NC)"
	docker compose -f docker/docker-compose.yml up -d

docker-up-prod:
	@make docker-generate-secrets
	@make docker-build
	@echo "$(CYAN)🏭 Starting production stack (bookworm DB, mounted secrets)...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml up -d

docker-down:
	@echo "$(RED)🛑 Stopping all containers...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml down || \
	docker compose -f docker/docker-compose.yml down

docker-clean:
	@make docker-down
	@echo "$(MAGENTA)🧹 Removing volumes and orphaned containers...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml down -v --remove-orphans || \
	docker compose -f docker/docker-compose.yml down -v --remove-orphans

# --- Logs ---
docker-logs:
	@echo "$(BLUE)📋 Following all container logs...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml logs -f || \
	docker compose -f docker/docker-compose.yml logs -f

docker-log-app:
	@echo "$(BLUE)📱 Following app logs...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml logs -f app || \
	docker compose -f docker/docker-compose.yml logs -f app

docker-log-db:
	@echo "$(BLUE)🗄️ Following database logs...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml logs -f db || \
	docker compose -f docker/docker-compose.yml logs -f db

docker-log-pgadmin:
	@echo "$(BLUE)🖥️ Following pgAdmin logs...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml logs -f pgadmin || \
	docker compose -f docker/docker-compose.yml logs -f pgadmin

docker-log-tail:
	@echo "$(BLUE)📜 Last 100 lines of app logs...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml logs --tail=100 app || \
	docker compose -f docker/docker-compose.yml logs --tail=100 app

# --- Container Access ---
docker-shell:
	@echo "$(BLUE)🐚 Opening shell in running app container...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml exec app sh || \
	docker compose -f docker/docker-compose.yml exec app sh

docker-bash:
	@echo "$(BLUE)🐚 Opening bash in running app container...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml exec app bash || \
	docker compose -f docker/docker-compose.yml exec app bash

docker-python:
	@echo "$(BLUE)🐍 Starting Python REPL in app container...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml exec app python || \
	docker compose -f docker/docker-compose.yml exec app python

docker-exec:
	@if [ -z "$(cmd)" ]; then \
		echo "$(RED)❌ Usage: make docker-exec cmd='your command here'$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)⚙️ Executing in app container: $(cmd)$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml exec app $(cmd) || \
	docker compose -f docker/docker-compose.yml exec app $(cmd)

# --- Inspection ---
docker-ps:
	@echo "$(BLUE)📊 Container status:$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml ps || \
	docker compose -f docker/docker-compose.yml ps

docker-stats:
	@echo "$(BLUE)📈 Live container statistics (Ctrl+C to stop):$(NC)"
	docker stats $$(docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml ps -q)

docker-inspect-app:
	@echo "$(BLUE)🔍 App container details:$(NC)"
	@ID=$$(docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml ps -q app || docker compose -f docker/docker-compose.yml ps -q app); \
	if [ -z "$$ID" ]; then \
		echo "$(RED)App container not found$(NC)"; \
	else \
		docker inspect "$$ID" | jq -r '{Name: .Name, Status: .State.Status, IP: .NetworkSettings.Networks[].IPAddress // "N/A", Ports: .NetworkSettings.Ports}' 2>/dev/null || \
		docker inspect "$$ID"; \
	fi

# --- Maintenance ---
docker-prune:
	@echo "$(RED)🗑️ Pruning unused Docker resources...$(NC)"
	@echo "$(YELLOW)This will remove:$(NC)"
	@echo " • Stopped containers"
	@echo " • Unused networks"
	@echo " • Dangling images"
	@echo " • Build cache"
	@echo
	@read -p "$(YELLOW)Continue? [y/N]: $(NC)" confirm; \
	if [ "$$confirm" = "y" ] || [ "$$confirm" = "Y" ]; then \
		docker system prune -a --volumes -f; \
		echo "$(GREEN)✅ Prune complete.$(NC)"; \
	else \
		echo "$(GRAY)Cancelled.$(NC)"; \
	fi

docker-images:
	@echo "$(BLUE)🖼️ Docker images in project:$(NC)"
	docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}"

docker-volumes:
	@echo "$(BLUE)💾 Docker volumes:$(NC)"
	docker volume ls
