# =============================================================================
# ROOT MAKEFILE
# =============================================================================

ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
export ROOT_DIR

# Scripts directory
SCRIPTS_DIR := $(ROOT_DIR)/scripts/bin
export SCRIPTS_DIR

# Include all modules
include $(ROOT_DIR)/mks/env.mk
include $(ROOT_DIR)/mks/secrets.mk
include $(ROOT_DIR)/mks/docker.mk
include $(ROOT_DIR)/mks/app.mk

.DEFAULT_GOAL := help

.PHONY: help

help:
	@$(MAKE) --no-print-directory _help_env
	@echo
	@$(MAKE) --no-print-directory _help_secrets
	@echo
	@$(MAKE) --no-print-directory _help_docker
	@echo
	@$(MAKE) --no-print-directory _help_app
