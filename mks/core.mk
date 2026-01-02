# =============================================================================
# CORE UTILITIES — ./mks/core.mk
# =============================================================================

SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

DRY_RUN ?= 0
VERBOSE ?= 0

MAKE_SILENT = $(MAKE) --no-print-directory

# ─────────────────────────────────────────────────────────────────────────────
# COLORS
# ─────────────────────────────────────────────────────────────────────────────
RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
BLUE   := \033[0;34m
CYAN   := \033[0;36m
GRAY   := \033[0;90m
RESET  := \033[0m

# ─────────────────────────────────────────────────────────────────────────────
# LOGGING
# ─────────────────────────────────────────────────────────────────────────────
define log_info
@printf "$(BLUE)[INFO]$(RESET) %s\n" "$(1)"
endef

define log_warn
@printf "$(YELLOW)[WARN]$(RESET) %s\n" "$(1)"
endef

define log_error
@printf "$(RED)[ERROR]$(RESET) %s\n" "$(1)" >&2
endef

define log_ok
@printf "$(GREEN)[OK]$(RESET) %s\n" "$(1)"
endef

# ─────────────────────────────────────────────────────────────────────────────
# ASSERTIONS
# ─────────────────────────────────────────────────────────────────────────────
define assert_file
@test -f "$(1)" || { $(call log_error,Missing file: $(1)); exit 1; }
endef

define assert_cmd
@command -v "$(1)" >/dev/null || { $(call log_error,Missing command: $(1)); exit 1; }
endef

# ─────────────────────────────────────────────────────────────────────────────
# EXECUTION WRAPPER
# ─────────────────────────────────────────────────────────────────────────────
define EXEC
@bash -euo pipefail -c '\
	trap "echo -e \"$(RED)[FAIL]$(RESET) $(1)\"" ERR; \
	echo -e "$(CYAN)[RUN]$(RESET) $(1)"; \
	if [ "$(VERBOSE)" = "1" ]; then set -x; fi; \
	if [ "$(DRY_RUN)" = "1" ]; then \
		echo "[DRY] $(2)"; \
	else \
		$(2); \
	fi; \
	echo -e "$(GREEN)[DONE]$(RESET) $(1)"; \
'
endef

# ─────────────────────────────────────────────────────────────────────────────
# HELP UTILS
# ─────────────────────────────────────────────────────────────────────────────
define HELP_SECTION
@printf "\n$(GREEN)%s$(RESET)\n" "$(1)"
endef
