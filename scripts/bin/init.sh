#!/bin/bash
# =============================================================================
# INITIALIZATION SCRIPT
# Ensures all scripts can find lib.sh and paths are set correctly
# =============================================================================

set -euo pipefail

if [[ -n "${BASH_SOURCE[0]}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "$0" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
else
    SCRIPT_DIR="$(pwd)"
fi

export PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export COMPOSE_DIR="$PROJECT_ROOT/docker/compose"
export COMPOSE_FILE="$PROJECT_ROOT/docker/compose/docker-compose.core.yml"
export SECRETS_DIR="$PROJECT_ROOT/docker/secrets"
export ENVS_DIR="$PROJECT_ROOT/envs"
export ACTIVE_ENV_FILE="$PROJECT_ROOT/.active-env"

if [[ -f "$SCRIPT_DIR/lib.sh" ]]; then
    source "$SCRIPT_DIR/lib.sh"
else
    echo "[ERROR] Cannot find lib.sh in $SCRIPT_DIR" >&2
    exit 1
fi
