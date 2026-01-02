#!/bin/bash
# =============================================================================
# CORE LIBRARY - Logging, assertions and utilities
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# PATH CONSTANTS
# -----------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$BIN_DIR/../.." && pwd)"
readonly COMPOSE_DIR="$PROJECT_ROOT/docker/compose"
readonly SECRETS_DIR="$PROJECT_ROOT/docker/secrets"

# -----------------------------------------------------------------------------
# COLOR CONSTANTS
# -----------------------------------------------------------------------------
readonly COLOR_RESET='\033[0m'
readonly COLOR_RED='\033[0;31m'
readonly COLOR_GREEN='\033[0;32m'
readonly COLOR_YELLOW='\033[1;33m'
readonly COLOR_BLUE='\033[0;34m'
readonly COLOR_CYAN='\033[0;36m'
readonly COLOR_GRAY='\033[0;90m'
readonly COLOR_BOLD='\033[1m'

# -----------------------------------------------------------------------------
# LOGGING FUNCTIONS
# -----------------------------------------------------------------------------
log::header() {
    printf "${COLOR_CYAN}==>${COLOR_RESET} ${COLOR_BOLD}%s${COLOR_RESET}\n" "$1"
}

log::info() {
    printf "${COLOR_BLUE}[INFO]${COLOR_RESET} %s\n" "$1"
}

log::success() {
    printf "${COLOR_GREEN}[OK]${COLOR_RESET} %s\n" "$1"
}

log::warn() {
    printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %s\n" "$1" >&2
}

log::error() {
    printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$1" >&2
}

log::debug() {
    [[ "${DEBUG:-0}" == "1" ]] && printf "${COLOR_GRAY}[DEBUG]${COLOR_RESET} %s\n" "$1"
}

log::fatal() {
    log::error "$1"
    exit 1
}

# -----------------------------------------------------------------------------
# PATH HELPERS
# -----------------------------------------------------------------------------
bin::path() {
    echo "$BIN_DIR"
}

root::path() {
    echo "$PROJECT_ROOT"
}

compose::path() {
    echo "$COMPOSE_DIR"
}

secrets::path() {
    echo "$SECRETS_DIR"
}

# -----------------------------------------------------------------------------
# VALIDATION FUNCTIONS
# -----------------------------------------------------------------------------
validate::command_exists() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log::fatal "Command '$cmd' not found. Please install it first."
    fi
}

validate::file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        log::error "File not found: $file"
        return 1
    fi
}

validate::directory_exists() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log::error "Directory not found: $dir"
        return 1
    fi
}

validate::docker_running() {
    if ! docker info &>/dev/null; then
        log::fatal "Docker daemon is not running. Please start Docker first."
    fi
}

validate::active_env() {
    local active_env_file="$PROJECT_ROOT/.active-env"
    if [[ ! -f "$active_env_file" ]]; then
        log::error "No active environment set. Run 'make env' first."
        return 1
    fi

    local env_name
    read -r env_name < "$active_env_file" || {
        log::error "Failed to read active environment file"
        return 1
    }

    local env_file="$PROJECT_ROOT/envs/.env.$env_name"
    if [[ ! -f "$env_file" ]]; then
        log::error "Environment file not found: $env_file"
        return 1
    fi

    echo "$env_name"
}

# -----------------------------------------------------------------------------
# ENVIRONMENT LOADING
# -----------------------------------------------------------------------------
load::environment() {
    local env_name
    env_name=$(validate::active_env) || return 1

    # Load environment variables from the active environment
    local env_file="$PROJECT_ROOT/envs/.env.$env_name"

    # Check if environment is already loaded
    if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]] && [[ -n "${COMPOSE_PROFILES:-}" ]]; then
        log::debug "Environment already loaded"
        return 0
    fi

    # Export variables from env file
    if [[ -f "$env_file" ]]; then
        # Source the environment file while handling errors
        set -a  # Automatically export all variables
        if ! source "$env_file" 2>/dev/null; then
            log::error "Failed to load environment file: $env_file"
            set +a
            return 1
        fi
        set +a

        log::debug "Loaded environment: $env_name"
    else
        log::error "Environment file not found: $env_file"
        return 1
    fi

    echo "$env_name"
}

# -----------------------------------------------------------------------------
# DOCKER COMPOSE HELPER
# -----------------------------------------------------------------------------
compose::command() {
    local cmd="$1"
    shift
    local compose_file="$COMPOSE_DIR/docker-compose.core.yml"

    validate::file_exists "$compose_file" || return 1
    validate::docker_running || return 1

    # Set Docker Compose project name and profiles from environment
    local compose_args=(
        "--project-directory" "$COMPOSE_DIR"
        "--file" "$compose_file"
    )

    # Use project name and profiles from environment if set
    if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
        compose_args+=("--project-name" "$COMPOSE_PROJECT_NAME")
    fi

    if [[ -n "${COMPOSE_PROFILES:-}" ]]; then
        compose_args+=("--profile" "$COMPOSE_PROFILES")
    fi

    log::debug "Executing: docker compose ${compose_args[*]} $cmd $*"

    # Execute docker compose command
    if ! docker compose "${compose_args[@]}" "$cmd" "$@"; then
        log::error "Docker Compose command failed: $cmd"
        return 1
    fi
}
