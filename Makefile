# =============================================================================
# WORKING UNIVERSAL LOGGING WITH NESTING (SAFE)
# =============================================================================
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

RED    := \033[0;31m
GREEN  := \033[0;32m
CYAN   := \033[0;36m
RESET  := \033[0m

# ─────────────────────────────────────────────
# UNIVERSAL TARGET EXECUTOR
# ─────────────────────────────────────────────
define TARGET_EXEC
@LEVEL=${3:=0}; \
PREFIX="$$(printf '  %.0s' $$LEVEL)"; \
echo -e "$(CYAN)$$PREFIX[RUN]$(RESET) $(1)"; \
LEVEL=$$((LEVEL+1)); \
{ $(2); }; \
STATUS=$$?; \
LEVEL=$$((LEVEL-1)); \
if [ $$STATUS -eq 0 ]; then \
    echo -e "$(GREEN)$$PREFIX[SUCCESS]$(RESET) $(1)"; \
else \
    echo -e "$(RED)$$PREFIX[FAILED]$(RESET) $(1)"; \
    exit $$STATUS; \
fi
endef

# ─────────────────────────────────────────────
# TEST TARGETS
# ─────────────────────────────────────────────
.PHONY: all task1 task2 task3 failtask

all: task1

task1:
	$(call TARGET_EXEC,"Task 1",\
		echo "Running Task 1"; \
		sleep 1; \
		$(MAKE) task2 LEVEL=1; \
		$(MAKE) failtask LEVEL=1 \
	)

task2:
	$(call TARGET_EXEC,"Task 2",\
		echo "Running Task 2"; \
		sleep 1; \
		$(MAKE) task3 LEVEL=2 \
	)

task3:
	$(call TARGET_EXEC,"Task 3",\
		echo "Running Task 3"; \
		sleep 1 \
	)

failtask:
	$(call TARGET_EXEC,"Failing Task",\
		echo "This will fail"; \
		exit 1 \
	)
