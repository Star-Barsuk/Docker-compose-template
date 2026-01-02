# =============================================================================
# ENV MAKEFILE
# =============================================================================

ENV_DIR := $(ROOT_DIR)/envs
ACTIVE_ENV_FILE := $(ROOT_DIR)/.active-env
ENV_DIST := $(ENV_DIR)/.env.dist

.PHONY: env \
	env-status env-list env-validate env-diff \
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
		$(MAKE_SILENT) _env_detect && \
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

## env-validate — ensure env defines only known vars
env-validate:
	$(call EXEC,Validate environment,\
		$(MAKE_SILENT) _env_assert_active && \
		$(call assert_file,$(ENV_DIST)) && \
		UNKNOWN=$$(comm -23 \
			<(grep -E '^[A-Z_][A-Z0-9_]*=' $(ENV_DIR)/.env.$$(cat $(ACTIVE_ENV_FILE)) | cut -d= -f1 | sort) \
			<(grep -E '^[A-Z_][A-Z0-9_]*=' $(ENV_DIST) | cut -d= -f1 | sort)); \
		if [ -n "$$UNKNOWN" ]; then \
			echo "$(RED)[ERROR]$(RESET) Unknown variables detected:"; \
			echo "$$UNKNOWN"; \
			exit 1; \
		else \
			echo "$(GREEN)[OK]$(RESET) Environment is valid"; \
		fi \
	)

## env-diff — diff env vs schema (informational)
env-diff:
	$(call EXEC,Diff vs env.dist,\
		$(MAKE_SILENT) _env_assert_active && \
		diff -u $(ENV_DIST) $(ENV_DIR)/.env.$$(cat $(ACTIVE_ENV_FILE)) || true \
	)

# ─────────────────────────────────────────────────────────────────────────────
# INTERNALS
# ─────────────────────────────────────────────────────────────────────────────

_env_detect:
	@ls $(ENV_DIR)/.env.* 2>/dev/null | \
		grep -vE '\.example$$|\.dist$$' | \
		sed 's|.*/.env.||' || true

_env_menu:
	@echo "Select environment:"; \
	select ENV in $$($(MAKE_SILENT) _env_detect); do \
		if [ -n "$$ENV" ]; then \
			echo "$$ENV" > $(ACTIVE_ENV_FILE); \
			printf "$(GREEN)[OK]$(RESET) Active env set to '%s'\n" "$$ENV"; \
			break; \
		fi; \
	done

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
	printf "$(CYAN)Active environment:$(RESET) %s\n\n" "$$(cat $(ACTIVE_ENV_FILE))"; \
	for v in $(ENV_DIST_VARS); do \
		if [ -n "$${!v+x}" ]; then \
			printf "$(GREEN)✔$(RESET) %-30s = %s\n" "$$v" "$${!v}"; \
		else \
			printf "$(YELLOW)∅$(RESET) %-30s (not set)\n" "$$v"; \
		fi; \
	done

_help_env:
	@printf "$(GREEN)Environment$(RESET)\n"
	@printf "  $(CYAN)env$(RESET)           Select environment\n"
	@printf "  $(CYAN)env-list$(RESET)      List environments\n"
	@printf "  $(CYAN)env-status$(RESET)    Show env variables\n"
	@printf "  $(CYAN)env-validate$(RESET)  Validate env vs schema\n"
	@printf "  $(CYAN)env-diff$(RESET)      Diff env vs env.dist\n"
