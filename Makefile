# === Configuration ===
# Project name — can be overridden in .env file (e.g., PROJECT=my-app)
PROJECT ?= database-module

# Tools
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
GRAY=\033[38;5;245m
NC=\033[0m

# === All targets ===
.PHONY: help \
        install install-dev uninstall \
        run lint format fix check lint-changed \
        test clean \
        docker-generate-secrets docker-rotate-secrets docker-build \
        docker-up-dev docker-up-prod docker-down docker-clean \
        docker-logs docker-log-app docker-log-db docker-log-pgadmin docker-log-tail \
        docker-shell docker-bash docker-python docker-exec \
        docker-ps docker-stats docker-inspect-app docker-audit \
        docker-prune docker-images docker-volumes

# --- Help ---
help:
	@echo "$(WHITE)🚀 $(PROJECT) Development Toolkit$(NC)"
	@echo
	@echo "$(ORANGE)■ Environment$(NC)"
	@printf "  $(GREEN)install$(NC)%-20s Install core dependencies\n" ""
	@printf "  $(GREEN)install-dev$(NC)%-15s Install core + dev tools\n" ""
	@printf "  $(RED)uninstall$(NC)%-18s Remove virtual environments\n" ""
	@echo
	@echo "$(ORANGE)■ Development$(NC)"
	@printf "  $(CYAN)run$(NC)%-22s Run app locally\n" ""
	@printf "  $(CYAN)lint$(NC)%-21s Lint all Python files\n" ""
	@printf "  $(CYAN)format$(NC)%-19s Format code\n" ""
	@printf "  $(CYAN)fix$(NC)%-22s Auto-fix issues\n" ""
	@printf "  $(CYAN)check$(NC)%-20s Run CI checks (lint + format)\n" ""
	@printf "  $(CYAN)lint-changed$(NC)%-12s Lint only changed files\n" ""
	@echo
	@echo "$(ORANGE)■ Docker$(NC)"
	@printf "  $(BLUE)docker-generate-secrets$(NC)%-8s Generate strong passwords\n" ""
	@printf "  $(BLUE)docker-rotate-secrets$(NC)%-9s Rotate passwords and restart\n" ""
	@printf "  $(BLUE)docker-build$(NC)%-18s Build app image\n" ""
	@printf "  $(BLUE)docker-up-dev$(NC)%-15s Start development stack\n" ""
	@printf "  $(BLUE)docker-up-prod$(NC)%-14s Start production stack\n" ""
	@printf "  $(BLUE)docker-down$(NC)%-17s Stop all containers\n" ""
	@printf "  $(BLUE)docker-clean$(NC)%-16s Stop and remove volumes\n" ""
	@printf "  $(BLUE)docker-logs$(NC)%-18s Follow all container logs\n" ""
	@printf "  $(BLUE)docker-log-app$(NC)%-14s Follow app logs\n" ""
	@printf "  $(BLUE)docker-log-db$(NC)%-15s Follow database logs\n" ""
	@printf "  $(BLUE)docker-log-pgadmin$(NC)%-8s Follow pgAdmin logs\n" ""
	@printf "  $(BLUE)docker-shell$(NC)%-15s Open shell in app container\n" ""
	@printf "  $(BLUE)docker-exec cmd='... '$(NC)%-8s Run command in app container\n" ""
	@printf "  $(BLUE)docker-ps$(NC)%-21s Show container status\n" ""
	@printf "  $(BLUE)docker-stats$(NC)%-18s Show live resource usage\n" ""
	@printf "  $(BLUE)docker-audit$(NC)%-17s Basic security audit\n" ""
	@echo
	@echo "$(ORANGE)■ Maintenance$(NC)"
	@printf "  $(MAGENTA)test$(NC)%-23s Run tests (placeholder)\n" ""
	@printf "  $(MAGENTA)clean$(NC)%-22s Clean Python caches\n" ""
	@printf "  $(MAGENTA)docker-prune$(NC)%-14s Remove unused Docker resources\n" ""
	@echo
	@echo "$(GRAY)▶ $(WHITE)make install$(GRAY) to get started • $(WHITE)make docker-up-dev$(GRAY) to run containers$(NC)"

# --- Setup ---
install:
	@echo "$(GREEN)📦 Installing core dependencies...$(NC)"
	uv sync --no-dev
	@echo "$(GREEN)✅ Core dependencies installed.$(NC)"

install-dev:
	@echo "$(GREEN)🔧 Installing development dependencies...$(NC)"
	uv sync --extra dev
	@echo "$(GREEN)✅ Dev tools ready.$(NC)"

uninstall:
	@echo "$(RED)🗑️ Removing virtual environments...$(NC)"
	rm -rf .venv venv env >/dev/null 2>&1 || true
	@echo "$(GREEN)✅ Virtual environments removed.$(NC)"

# --- Run ---
run: run-main
run-main:
	@echo "$(CYAN)🚀 Starting $(PROJECT) in development mode...$(NC)"
	$(PYTHON) -m src.main

# --- Lint & Format ---
lint:
	@echo "$(CYAN)🔍 Linting all files...$(NC)"
	$(RUFF) check . --output-format=concise

format:
	@echo "$(CYAN)🎨 Formatting code...$(NC)"
	$(RUFF) format .

check:
	@sh -c '\
		echo "$(CYAN)📊 Running static analysis (CI mode)...$(NC)"; \
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
			echo "$(GREEN)✨ Fixable issues resolved.$(NC)"; \
		else \
			echo "$(YELLOW)⚠ Some issues need manual fixing.$(NC)" >&2; \
			exit 1; \
		fi'

lint-changed:
	@echo "$(CYAN)🔍 Linting only changed Python files...$(NC)"
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

# --- Test ---
test:
	@echo "$(MAGENTA)🧪 Running tests... (add pytest later)$(NC)"
	@echo "$(GRAY)Hint:$(NC) Add 'pytest' to dev dependencies and update this target."

# --- Clean ---
clean:
	@echo "$(MAGENTA)🧹 Cleaning Python caches...$(NC)"
	find . -type d \( -name "__pycache__" -o -name ".mypy_cache" -o -name ".pytest_cache" -o -name ".ruff_cache" \) -prune -exec rm -rf {} + 2>/dev/null || true
	find . -type f \( -name "*.py[co]" -o -name ".coverage" -o -name ".coverage.*" -o -name "coverage.*" \) -delete 2>/dev/null || true
	@echo "$(GREEN)✅ Cleaning complete.$(NC)"

# === Docker Targets ===

# --- Secrets ---
docker-generate-secrets:
	@echo "$(GREEN)🔑 Generating strong random passwords...$(NC)"
	@mkdir -p docker/secrets
	@openssl rand -base64 32 > docker/secrets/db_password.txt
	@openssl rand -base64 32 > docker/secrets/pgadmin_password.txt
	@chmod 600 docker/secrets/*.txt
	@echo "$(GREEN)✅ Passwords saved in docker/secrets/$(NC)"

docker-rotate-secrets: docker-down docker-generate-secrets docker-up-prod
	@echo "$(YELLOW)🔄 Passwords rotated and services restarted.$(NC)"

# --- Build ---
docker-build:
	@echo "$(CYAN)🏗️ Building application image...$(NC)"
	docker compose -f docker/docker-compose.yml build app

# --- Start / Stop ---
docker-up-dev:
	@make docker-generate-secrets || true
	@echo "$(CYAN)🚀 Starting development stack...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.dev.yml up -d

docker-up-prod:
	@make docker-generate-secrets || true
	@make docker-build
	@echo "$(CYAN)🏭 Starting production stack...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml up -d

docker-down:
	@echo "$(RED)🛑 Stopping containers...$(NC)"
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

# --- Container access ---
docker-shell:
	@echo "$(BLUE)🐚 Opening shell in app container...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml exec app sh || \
	docker compose -f docker/docker-compose.yml exec app sh

docker-bash:
	@echo "$(BLUE)🐚 Opening bash in app container...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml exec app bash || \
	docker compose -f docker/docker-compose.yml exec app bash

docker-python:
	@echo "$(BLUE)🐍 Starting Python REPL in container...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml exec app python || \
	docker compose -f docker/docker-compose.yml exec app python

docker-exec:
	@if [ -z "$(cmd)" ]; then \
		echo "$(RED)❌ Usage: make docker-exec cmd='your command here'$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)⚙️ Running in app container: $(cmd)$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml exec app $(cmd) || \
	docker compose -f docker/docker-compose.yml exec app $(cmd)

# --- Inspection ---
docker-ps:
	@echo "$(BLUE)📊 Container status:$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml ps || \
	docker compose -f docker/docker-compose.yml ps

docker-stats:
	@echo "$(BLUE)📈 Live resource usage (Ctrl+C to stop):$(NC)"
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

docker-audit:
	@echo "$(BLUE)🔒 Basic Docker security audit...$(NC)"
	docker compose -f docker/docker-compose.yml -f docker/docker-compose.prod.yml ps -q | xargs docker inspect --format '{{.Name}}: Caps={{.HostConfig.CapAdd}} Drop={{.HostConfig.CapDrop}} Priv={{.HostConfig.Privileged}} User={{.Config.User}} ReadOnly={{.HostConfig.ReadonlyRootfs}}'
	@echo "$(BLUE)Project volumes:$(NC)"
	docker volume ls -f name=$(PROJECT)

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
	@echo "$(BLUE)🖼️ Project images:$(NC)"
	docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.Size}}\t{{.CreatedSince}}"

docker-volumes:
	@echo "$(BLUE)💾 Docker volumes:$(NC)"
	docker volume ls
