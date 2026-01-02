# =============================================================================
# DOCKER MAKEFILE MODULE
# =============================================================================

.PHONY: up stop down build clean nuke logs shell _help_docker

up:
	@bash $(SCRIPTS_DIR)/docker.sh up

stop:
	@bash $(SCRIPTS_DIR)/docker.sh stop

down:
	@bash $(SCRIPTS_DIR)/docker.sh down

build:
	@bash $(SCRIPTS_DIR)/docker.sh build

clean:
	@bash $(SCRIPTS_DIR)/docker.sh clean

nuke:
	@bash $(SCRIPTS_DIR)/docker.sh nuke

logs:
	@bash $(SCRIPTS_DIR)/docker.sh logs $(and $(FOLLOW),FOLLOW=$(FOLLOW)) $(and $(TAIL),TAIL=$(TAIL))

shell:
	@bash $(SCRIPTS_DIR)/docker.sh shell

_help_docker:
	@echo "Docker commands:"
	@echo "  make up                Start stack"
	@echo "  make stop              Stop stack"
	@echo "  make down              Remove stack (REMOVE_VOLUMES=1 for volumes)"
	@echo "  make build             Build images"
	@echo "  make clean             Safe cleanup"
	@echo "  make nuke              Full cleanup (danger!)"
	@echo "  make logs              View logs (FOLLOW=1 to follow, TAIL=lines)"
	@echo "  make shell             Enter container shell"
