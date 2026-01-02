# =============================================================================
# DOCKER MAKEFILE
# =============================================================================

.PHONY: up stop down build \
	logs shell ps stats df \
	clean nuke \
	_help_docker

up:
	$(call EXEC,Start containers,\
		$(MAKE) _docker_assert_env && docker compose up -d \
	)

stop:
	$(call EXEC,Stop containers,\
		docker compose stop \
	)

down:
	$(call EXEC,Down containers,\
		docker compose down \
	)

build:
	$(call EXEC,Build images,\
		docker compose build \
	)

clean:
	$(call EXEC,Clean docker resources,\
		$(MAKE) _docker_assert_stopped && \
		@# prune volumes/images/networks selectively \
	)

nuke:
	$(call EXEC,NUKE docker,\
		$(MAKE) _docker_assert_stopped && \
		@# full prune with explicit confirmation \
	)

logs:
	$(call EXEC,Logs,\
		docker compose logs -f \
	)

shell:
	$(call EXEC,Shell,\
		@# shell into service with postfix support \
	)

# ─────────────────────────────────────────────────────────────────────────────
# INTERNAL STATE CHECKS
# ─────────────────────────────────────────────────────────────────────────────

_docker_assert_env:
	@# Ensure env loaded + compose files exist

_docker_assert_stopped:
	@# If containers running → RED message + list → exit 1

_help_docker:
	@printf "$(GREEN)Docker$(RESET)\n"
	@printf "  $(CYAN)up$(RESET)                Start stack\n"
	@printf "  $(CYAN)stop$(RESET)              Stop stack\n"
	@printf "  $(CYAN)down$(RESET)              Remove stack\n"
	@printf "  $(CYAN)build$(RESET)             Build images\n"
	@printf "  $(CYAN)clean$(RESET)             Safe cleanup\n"
	@printf "  $(CYAN)nuke$(RESET)              Full cleanup (danger)\n"
	@printf "  $(CYAN)logs$(RESET)              View logs\n"
