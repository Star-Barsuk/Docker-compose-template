# =============================================================================
# DOCKER MAKEFILE MODULE
# =============================================================================

.PHONY: up stop down build \
	clean logs shell \
	ps stats df ports check-ports \
	validate \
	_help_docker

# -----------------------------------------------------------------------------
# SERVICE MANAGEMENT
# -----------------------------------------------------------------------------
up:
	@bash $(SCRIPTS_DIR)/docker.sh up \
		$(and $(FORCE),FORCE=$(FORCE))

stop:
	@bash $(SCRIPTS_DIR)/docker.sh stop \
		$(and $(FORCE),FORCE=$(FORCE))

down:
	@bash $(SCRIPTS_DIR)/docker.sh down \
		$(and $(REMOVE_VOLUMES),REMOVE_VOLUMES=$(REMOVE_VOLUMES)) \
		$(and $(FORCE),FORCE=$(FORCE))

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
	@bash $(SCRIPTS_DIR)/docker.sh clean \
		$(and $(FORCE),FORCE=$(FORCE)) $(TARGETS)

# -----------------------------------------------------------------------------
# MONITORING & INSPECTION
# -----------------------------------------------------------------------------
ps:
	@bash $(SCRIPTS_DIR)/docker.sh ps \
		$(ARGS)

stats:
	@bash $(SCRIPTS_DIR)/docker.sh stats \
		$(ARGS)

df:
	@bash $(SCRIPTS_DIR)/docker.sh df \
		$(ARGS)

inspect:
	@bash $(SCRIPTS_DIR)/docker.sh inspect \
		$(ARGS)

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

# -----------------------------------------------------------------------------
# HELP
# -----------------------------------------------------------------------------
_help_docker:
	@echo "---Docker commands:"
	@echo "Service Management:"
	@echo "  make up                Start stack (FORCE)"
	@echo "  make stop              Stop stack (FORCE)"
	@echo "  make down              Remove stack (REMOVE_VOLUMES, FORCE)"
	@echo "  make build             Build images"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean [TARGETS]   (containers|images|volumes|networks|cache|all)"
	@echo ""
	@echo "Monitoring:"
	@echo "  make ps | stats | df | ports | check-ports"
	@echo ""
	@echo "Interactive:"
	@echo "  make logs [ARGS]       View logs"
	@echo "  make shell [SERVICE]   Enter container shell"
