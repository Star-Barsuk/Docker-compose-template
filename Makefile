# =============================================================================
# CLEAN, PRODUCTION-READY UNIVERSAL LOGGING EXECUTOR
# =============================================================================
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# ─────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────
DRY_RUN ?= 0
VERBOSE ?= 0   # 0 = чистый лог, 1 = подробный вывод команд

RED    := \033[0;31m
GREEN  := \033[0;32m
YELLOW := \033[1;33m
CYAN   := \033[0;36m
RESET  := \033[0m

# ─────────────────────────────────────────────
# UNIVERSAL EXECUTOR
# ─────────────────────────────────────────────
# TARGET_EXEC("Name", shell-commands, LEVEL, STOP_ON_FAIL)
define TARGET_EXEC
@LEVEL=${3:=0}; \
STOP_ON_FAIL=${4:=1}; \
PREFIX="$$(printf '  %.0s' $$LEVEL)"; \
echo -e "$(CYAN)$$PREFIX[RUN]$(RESET) $(1)"; \
LEVEL=$$((LEVEL+1)); \
STATUS=0; \
if [ $(DRY_RUN) -eq 1 ]; then \
    echo -e "$(YELLOW)$$PREFIX[DRY_RUN]$(RESET) $(1)"; \
else \
    if [ $(VERBOSE) -eq 1 ]; then set -x; fi; \
    { $(2); } || STATUS=$$?; \
    if [ $(VERBOSE) -eq 1 ]; then set +x; fi; \
fi; \
LEVEL=$$((LEVEL-1)); \
if [ $$STATUS -eq 0 ]; then \
    echo -e "$(GREEN)$$PREFIX[SUCCESS]$(RESET) $(1)"; \
else \
    echo -e "$(RED)$$PREFIX[FAILED]$(RESET) $(1) (status=$$STATUS)"; \
    if [ $$STOP_ON_FAIL -eq 1 ]; then exit $$STATUS; fi; \
fi
endef

# ─────────────────────────────────────────────
# SAFE MAKE WRAPPER
# ─────────────────────────────────────────────
# safe_make <target> <level>
safe_make = bash -c '$(MAKE) -s $(1) LEVEL=$(2) STOP_ON_FAIL=0 || true'

# ─────────────────────────────────────────────
# TEST TARGETS
# ─────────────────────────────────────────────
.PHONY: all task1 task2 task3 failtask

all: task1

task1:
	$(call TARGET_EXEC,"Task 1",\
		echo "Running Task 1"; sleep 1; \
		$(call safe_make,task2,1); \
		$(call safe_make,failtask,1),\
	0,1)

task2:
	$(call TARGET_EXEC,"Task 2",\
		echo "Running Task 2"; sleep 1; \
		$(call safe_make,task3,2),\
	1,0)

task3:
	$(call TARGET_EXEC,"Task 3",\
		echo "Running Task 3"; sleep 1,\
	2,0)

failtask:
	$(call TARGET_EXEC,"Failing Task",\
		echo "This will fail"; exit 1,\
	1,0)
