# =============================================================================
# ENV MAKEFILE
# =============================================================================

ENV_DIR := $(ROOT_DIR)/envs
ACTIVE_ENV_FILE := $(ROOT_DIR)/.active-env
ENV_DIST := $(ENV_DIR)/.env.dist

.PHONY: env \
	env-status env-list env-validate \
	_help_env

# ─────────────────────────────────────────────────────────────────────────────
# VARIABLE DISCOVERY (schema-driven)
# ─────────────────────────────────────────────────────────────────────────────

ENV_DIST_VARS = $(shell \
	grep -E '^[A-Z_][A-Z0-9_]*=' $(ENV_DIST) | \
	cut -d= -f1 | sort -u \
)

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC TARGETS
# ─────────────────────────────────────────────────────────────────────────────

## env — interactive environment selector
env:
	$(call EXEC,Select environment,\
		$(MAKE_SILENT) _env_menu \
	)

## env-status — show active env + known variables
env-status:
	$(call EXEC,Show environment status,\
		$(MAKE_SILENT) _env_assert_active && \
		$(MAKE_SILENT) _env_dump \
	)

## env-list — list available environments
env-list:
	$(call EXEC,List environments,\
		$(MAKE_SILENT) _env_detect \
	)

## env-validate — internal guard to prevent unknown vars
env-validate:
	$(call EXEC,Validate environment,\
		$(MAKE_SILENT) _env_assert_active && \
		UNKNOWN=$$(comm -23 \
			<(grep -E '^[A-Z_][A-Z0-9_]*=' $(ENV_DIR)/.env.$$(cat $(ACTIVE_ENV_FILE)) | cut -d= -f1 | sort) \
			<(grep -E '^[A-Z_][A-Z0-9_]*=' $(ENV_DIST) | cut -d= -f1 | sort)); \
		if [ -n "$$UNKNOWN" ]; then \
			printf "$(RED)[ERROR]$(RESET) Unknown variables detected:\n"; \
			printf "%s\n" "$$UNKNOWN"; \
			exit 1; \
		else \
			printf "$(GREEN)[OK]$(RESET) Environment is valid\n"; \
		fi \
	)

# ─────────────────────────────────────────────────────────────────────────────
# INTERNALS
# ─────────────────────────────────────────────────────────────────────────────

_env_detect:
	@ls $(ENV_DIR)/.env.* 2>/dev/null | \
		grep -vE '\.example$$|\.dist$$' | \
		sed 's|.*/.env.||' || true

_env_menu:
	@ENVS="$$( $(MAKE_SILENT) _env_detect )"; \
	if [ -z "$$ENVS" ]; then \
		printf "$(RED)[ERROR]$(RESET) No environments found\n"; \
		exit 1; \
	fi; \
	set -- $$ENVS; \
	printf "Select environment:\n"; \
	i=1; \
	for e in "$$@"; do \
		printf "  %d) %s\n" $$i "$$e"; \
		i=$$((i+1)); \
	done; \
	printf "#? "; \
	read choice || true; \
	if printf "%s" "$$choice" | grep -Eq '^[0-9]+$$' && [ "$$choice" -ge 1 ] && [ "$$choice" -le "$$#" ]; then \
		ENV="$${!choice}"; \
	else \
		ENV="$$1"; \
	fi; \
	printf "%s\n" "$$ENV" > $(ACTIVE_ENV_FILE); \
	printf "$(GREEN)[OK]$(RESET) Active env set to '%s'\n" "$$ENV"

_env_assert_active:
	@if [ ! -f "$(ACTIVE_ENV_FILE)" ]; then \
		echo "$(RED)[ERROR]$(RESET) No active environment selected"; \
		exit 1; \
	fi; \
	if [ ! -f "$(ENV_DIR)/.env.$$(cat $(ACTIVE_ENV_FILE))" ]; then \
		echo "$(RED)[ERROR]$(RESET) Active env file missing"; \
		exit 1; \
	fi

_env_dump:
	@set -a; \
	. "$(ENV_DIR)/.env.$$(cat $(ACTIVE_ENV_FILE))"; \
	set +a; \
	printf "$(CYAN)Active environment:$(RESET) %s\n" "$$(cat $(ACTIVE_ENV_FILE))"; \
	for v in $(ENV_DIST_VARS); do \
		if [ -n "$${!v+x}" ]; then \
			if [ -z "$(SHOW)" ] || [ "$(SHOW)" = "set" ] || [ "$(SHOW)" = "all" ]; then \
				printf "$(GREEN)✔$(RESET) %-30s = %s\n" "$$v" "$${!v}"; \
			fi; \
		else \
			if [ "$(SHOW)" = "unset" ] || [ "$(SHOW)" = "all" ]; then \
				printf "$(YELLOW)∅$(RESET) %-30s (not set)\n" "$$v"; \
			fi; \
		fi; \
	done

_help_env:
	@printf "$(GREEN)Environment$(RESET)\n"
	@printf "  $(CYAN)env$(RESET)           Select environment\n"
	@printf "  $(CYAN)env-list$(RESET)      List environments\n"
	@printf "  $(CYAN)env-status$(RESET)    Show env variables (default: only set)\n"
	@printf "  $(CYAN)env-status SHOW=all$(RESET)  Show all variables\n"
	@printf "  $(CYAN)env-status SHOW=unset$(RESET)  Show only missing variables\n"
