# =============================================================================
# DOCKER MAKEFILE MODULE
# =============================================================================

.PHONY: up stop down build clean nuke logs shell ps stats df ports check-ports inspect validate config images exec top events _help_docker

# -----------------------------------------------------------------------------
# SERVICE MANAGEMENT
# -----------------------------------------------------------------------------
up:
	@bash $(SCRIPTS_DIR)/docker.sh up $(and $(FORCE),FORCE=$(FORCE))

stop:
	@bash $(SCRIPTS_DIR)/docker.sh stop $(and $(FORCE),FORCE=$(FORCE))

down:
	@bash $(SCRIPTS_DIR)/docker.sh down $(and $(REMOVE_VOLUMES),REMOVE_VOLUMES=$(REMOVE_VOLUMES)) $(and $(FORCE),FORCE=$(FORCE))

build:
	@bash $(SCRIPTS_DIR)/docker.sh build \
		$(and $(NO_CACHE),NO_CACHE=$(NO_CACHE)) \
		$(and $(FORCE),FORCE=$(FORCE)) \
		$(and $(PROGRESS),PROGRESS=$(PROGRESS)) \
		$(and $(APP_VERSION),APP_VERSION=$(APP_VERSION))

# -----------------------------------------------------------------------------
# CLEANUP
# -----------------------------------------------------------------------------
clean:
	@bash $(SCRIPTS_DIR)/docker.sh clean $(and $(FORCE),FORCE=$(FORCE)) $(TARGETS)

nuke:
	@bash $(SCRIPTS_DIR)/docker.sh nuke $(and $(FORCE),FORCE=$(FORCE))

# -----------------------------------------------------------------------------
# MONITORING & INSPECTION
# -----------------------------------------------------------------------------
ps:
	@bash $(SCRIPTS_DIR)/docker.sh ps $(ARGS)

stats:
	@bash $(SCRIPTS_DIR)/docker.sh stats $(ARGS)

df:
	@bash $(SCRIPTS_DIR)/docker.sh df $(ARGS)

inspect:
	@bash $(SCRIPTS_DIR)/docker.sh inspect $(ARGS)

ports:
	@bash $(SCRIPTS_DIR)/docker.sh ports

check-ports:
	@bash $(SCRIPTS_DIR)/docker.sh check-ports

# -----------------------------------------------------------------------------
# INTERACTIVE COMMANDS
# -----------------------------------------------------------------------------
logs:
	@bash $(SCRIPTS_DIR)/docker.sh logs \
		$(and $(FOLLOW),--follow) \
		$(and $(TAIL),--tail=$(TAIL)) \
		$(and $(SINCE),--since=$(SINCE)) \
		$(and $(UNTIL),--until=$(UNTIL)) \
		$(and $(TIMESTAMPS),--timestamps) \
		$(ARGS)

shell:
	@bash $(SCRIPTS_DIR)/docker.sh shell $(ARGS)

# -----------------------------------------------------------------------------
# VALIDATION & CONFIGURATION
# -----------------------------------------------------------------------------
validate:
	@bash $(SCRIPTS_DIR)/docker.sh validate

config:
	@bash $(SCRIPTS_DIR)/docker.sh config

# -----------------------------------------------------------------------------
# DIRECT DOCKER COMPOSE COMMANDS (PASSTHROUGH)
# -----------------------------------------------------------------------------
images:
	@bash $(SCRIPTS_DIR)/docker.sh images $(ARGS)

exec:
	@bash $(SCRIPTS_DIR)/docker.sh exec $(ARGS)

top:
	@bash $(SCRIPTS_DIR)/docker.sh top $(ARGS)

events:
	@bash $(SCRIPTS_DIR)/docker.sh events $(ARGS)

# -----------------------------------------------------------------------------
# HELP
# -----------------------------------------------------------------------------
_help_docker:
	@echo "Docker commands:"
	@echo ""
	@echo "Service Management:"
	@echo "  make up                Start stack (FORCE=1 to restart)"
	@echo "  make stop              Stop stack (FORCE=1 for immediate)"
	@echo "  make down              Remove stack (REMOVE_VOLUMES=1 for volumes, FORCE=1 to skip confirm)"
	@echo "  make build             Build images (NO_CACHE=1 to disable cache, FORCE=1 to force, PROGRESS=plain/auto/quiet)"
	@echo "                         APP_VERSION=<version> to set version"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean [TARGETS]   Clean specific resources"
	@echo "                         TARGETS: containers, images, volumes, networks, cache, all"
	@echo "                         Example: make clean containers images"
	@echo "                         Use FORCE=1 for dangerous operations"
	@echo ""
	@echo "Monitoring & Inspection:"
	@echo "  make ps                List containers (use ARGS for docker-compose ps args)"
	@echo "  make stats             Live container statistics"
	@echo "  make df                Docker disk usage analysis"
	@echo "  make inspect [SERVICE] Inspect container details"
	@echo "  make ports             Show all service port mappings"
	@echo "  make check-ports       Check port availability"
	@echo ""
	@echo "Interactive:"
	@echo "  make logs [ARGS]       View logs"
	@echo "        FOLLOW=1         Follow log output"
	@echo "        TAIL=N           Number of lines (default: 100)"
	@echo "        SINCE=TIMESTAMP  Logs since timestamp"
	@echo "        UNTIL=TIMESTAMP  Logs until timestamp"
	@echo "        TIMESTAMPS=1     Show timestamps"
	@echo "        ARGS='svc1 svc2' Multiple services"
	@echo "  make shell [SERVICE]   Enter container shell"
	@echo ""
	@echo "Validation & Configuration:"
	@echo "  make validate          Validate docker-compose configuration"
	@echo "  make config            Show raw docker-compose configuration"
