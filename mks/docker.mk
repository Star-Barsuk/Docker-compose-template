# =============================================================================
# DOCKER MAKEFILE (wrapper)
# =============================================================================

.PHONY: up stop down build logs shell clean nuke _help_docker

DOCKER_SCRIPT := $(ROOT_DIR)/scripts/bin/docker.sh

up:
	@$(DOCKER_SCRIPT) up

stop:
	@$(DOCKER_SCRIPT) stop

down:
	@$(DOCKER_SCRIPT) down

build:
	@$(DOCKER_SCRIPT) build

clean:
	@$(DOCKER_SCRIPT) clean

nuke:
	@$(DOCKER_SCRIPT) nuke

logs:
	@$(DOCKER_SCRIPT) logs

shell:
	@$(DOCKER_SCRIPT) shell

_help_docker:
	@printf "$(GREEN)Docker$(RESET)\n"
	@printf "  $(CYAN)up$(RESET)                Start stack\n"
	@printf "  $(CYAN)stop$(RESET)              Stop stack\n"
	@printf "  $(CYAN)down$(RESET)              Remove stack\n"
	@printf "  $(CYAN)build$(RESET)             Build images\n"
	@printf "  $(CYAN)clean$(RESET)             Safe cleanup\n"
	@printf "  $(CYAN)nuke$(RESET)              Full cleanup (danger)\n"
	@printf "  $(CYAN)logs$(RESET)              View logs\n"
