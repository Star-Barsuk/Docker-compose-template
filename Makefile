# =============================================================================
# ROOT MAKEFILE
# =============================================================================

ROOT_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
MKS_DIR := $(ROOT_DIR)/mks

include $(MKS_DIR)/env.mk
include $(MKS_DIR)/secrets.mk
include $(MKS_DIR)/docker.mk
include $(MKS_DIR)/app.mk

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
