#!/bin/bash
# =============================================================================
# CORE LIBRARY
# Shared functions and utilities for all scripts
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# COLOR OUTPUT
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
    COLOR_RESET=$'\033[0m'
    COLOR_RED=$'\033[0;31m'
    COLOR_GREEN=$'\033[0;32m'
    COLOR_YELLOW=$'\033[1;33m'
    COLOR_BLUE=$'\033[0;34m'
    COLOR_CYAN=$'\033[0;36m'
    COLOR_GRAY=$'\033[0;90m'
    COLOR_BOLD=$'\033[1m'
else
    COLOR_RESET=''; COLOR_RED=''; COLOR_GREEN=''; COLOR_YELLOW=''
    COLOR_BLUE=''; COLOR_CYAN=''; COLOR_GRAY=''; COLOR_BOLD=''
fi

export COLOR_RESET COLOR_RED COLOR_GREEN COLOR_YELLOW COLOR_BLUE COLOR_CYAN COLOR_GRAY COLOR_BOLD

# -----------------------------------------------------------------------------
# LOGGING FUNCTIONS
# -----------------------------------------------------------------------------
log::header()   { printf "${COLOR_CYAN}==>${COLOR_RESET} ${COLOR_BOLD}%s${COLOR_RESET}\n" "$1"; }
log::info()     { printf "${COLOR_BLUE}[INFO]${COLOR_RESET} %s\n" "$1"; }
log::success()  { printf "${COLOR_GREEN}[OK]${COLOR_RESET} %s\n" "$1"; }
log::warn()     { printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %s\n" "$1" >&2; }
log::error()    { printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$1" >&2; }
log::debug()    { [[ "${LOG_LEVEL:-}" == "DEBUG" ]] && printf "${COLOR_GRAY}[DEBUG]${COLOR_RESET} %s\n" "$1"; }
log::fatal()    { log::error "$1"; exit 1; }

export -f log::header log::info log::success log::warn log::error log::debug log::fatal

# -----------------------------------------------------------------------------
# PATH HELPERS
# -----------------------------------------------------------------------------
root::path()    { echo "$PROJECT_ROOT"; }
compose::path() { echo "$COMPOSE_DIR"; }
secrets::path() { echo "$SECRETS_DIR"; }
envs::path()    { echo "$ENVS_DIR"; }
active_env_file() { echo "$ACTIVE_ENV_FILE"; }

# Get relative path from project root
relpath() {
    local path="${1:-}"
    local root="${PROJECT_ROOT%/}/"
    # Remove the root path prefix
    echo "${path#$root}"
}

export -f root::path compose::path secrets::path envs::path active_env_file relpath

# -----------------------------------------------------------------------------
# VALIDATION FUNCTIONS
# -----------------------------------------------------------------------------
validate::file_exists() {
    [[ -f "${1:-}" ]] || { log::error "File not found: ${1:-}"; return 1; }
}

validate::dir_exists() {
    [[ -d "${1:-}" ]] || { log::error "Directory not found: ${1:-}"; return 1; }
}

validate::command_exists() {
    command -v "${1:-}" >/dev/null 2>&1 || {
        log::error "Command '${1:-}' not found"; return 1;
    }
}

validate::docker_running() {
    docker info >/dev/null 2>&1 || {
        log::error "Docker daemon is not running"; return 1;
    }
}

validate::active_env() {
    [[ -f "${ACTIVE_ENV_FILE:-}" ]] || {
        log::error "No active environment. Run 'make env' first"; return 1;
    }

    local env_name
    read -r env_name < "${ACTIVE_ENV_FILE}" 2>/dev/null || {
        log::error "Failed to read active environment file"; return 1;
    }

    local env_file="${ENVS_DIR:-}/.env.$env_name"
    [[ -f "$env_file" ]] || {
        log::error "Environment file not found: $env_file"; return 1;
    }

    echo "$env_name"
}

export -f validate::file_exists validate::dir_exists validate::command_exists \
          validate::docker_running validate::active_env

# -----------------------------------------------------------------------------
# ENVIRONMENT LOADING
# -----------------------------------------------------------------------------
load::environment() {
    local env_name
    env_name=$(validate::active_env) || return 1

    local env_file="${ENVS_DIR:-}/.env.$env_name"

    if [[ -f "$env_file" ]]; then
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${key//[[:space:]]/}" ]] && continue

            key="${key%%[[:space:]]*}"
            [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue

            value="${value%%#*}"
            value="${value%"${value##*[![:space:]]}"}"

            if [[ "$value" =~ ^\"(.*)\"$ ]] || [[ "$value" =~ ^\'(.*)\'$ ]]; then
                value="${BASH_REMATCH[1]}"
            fi

            export "$key"="$value"
        done < "$env_file"

        log::debug "Loaded environment: $env_name"
    else
        log::error "Environment file not found: $env_file"
        return 1
    fi

    echo "$env_name"
}

export -f load::environment

# -----------------------------------------------------------------------------
# DOCKER COMPOSE HELPER
# -----------------------------------------------------------------------------
compose::cmd() {
    local env_name
    env_name=$(load::environment) || return 1

    validate::file_exists "$COMPOSE_FILE" || return 1
    validate::docker_running || return 1

    local args=(
        "--file" "$COMPOSE_FILE"
        "--project-directory" "$COMPOSE_DIR"
        "--env-file" "${ENVS_DIR:-}/.env.${env_name}"
    )

    [[ -n "${COMPOSE_PROJECT_NAME:-}" ]] && args+=("--project-name" "$COMPOSE_PROJECT_NAME")
    [[ -n "${COMPOSE_PROFILES:-}" ]] && args+=("--profile" "$COMPOSE_PROFILES")

    log::debug "Executing docker compose with env: $env_name"
    log::debug "Executing docker compose with args: ${args[*]} $*"

    docker compose "${args[@]}" "$@"
}

export -f compose::cmd

# -----------------------------------------------------------------------------
# FLAG PARSING
# -----------------------------------------------------------------------------
parse::flags() {
    export FORCE="${FORCE:-0}"
    export REMOVE_VOLUMES="${REMOVE_VOLUMES:-0}"
    export NO_CACHE="${NO_CACHE:-0}"

    local args=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force|-f)
                export FORCE=1
                shift
                ;;
            --volumes|-v)
                export REMOVE_VOLUMES=1
                shift
                ;;
            --no-cache)
                export NO_CACHE=1
                shift
                ;;
            --help|-h)
                # This is handled by main function
                args+=("$1")
                shift
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Return remaining arguments
    printf '%s\n' "${args[@]}"
}

export -f parse::flags

# -----------------------------------------------------------------------------
# NETWORK FUNCTIONS
# -----------------------------------------------------------------------------
network::get_host_ip() {
    local ip

    if [[ "$(uname -s)" == "Linux" ]] && command -v ip >/dev/null 2>&1; then
        ip=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')
    fi

    if [[ -z "$ip" ]] && command -v route >/dev/null 2>&1; then
        ip=$(route -n get default 2>/dev/null | grep interface | awk '{print $2}' | xargs ifconfig 2>/dev/null | grep "inet " | head -1 | awk '{print $2}')
    fi

    if [[ -z "$ip" ]]; then
        if [[ -f /.dockerenv ]]; then
            ip="host.docker.internal"
        else
            ip="localhost"
        fi
    fi

    echo "${ip:-localhost}"
}

network::check_port() {
    local port="${1:-}"
    local service="${2:-Unknown}"

    if [[ -z "$port" ]]; then
        log::warn "No port specified for $service"
        return 1
    fi

    local port_num
    port_num=$(echo "$port" | grep -oE '[0-9]+' | head -1)

    if [[ -z "$port_num" ]]; then
        log::warn "Invalid port format: $port for $service"
        return 1
    fi

    if command -v nc >/dev/null 2>&1; then
        if nc -z localhost "$port_num" 2>/dev/null; then
            printf "  %-20s %-10s ${COLOR_RED}%s${COLOR_RESET}\n" "$service" "$port" "BUSY"
            return 1
        else
            printf "  %-20s %-10s ${COLOR_GREEN}%s${COLOR_RESET}\n" "$service" "$port" "AVAILABLE"
            return 0
        fi
    elif command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":$port_num "; then
            printf "  %-20s %-10s ${COLOR_RED}%s${COLOR_RESET}\n" "$service" "$port" "BUSY"
            return 1
        else
            printf "  %-20s %-10s ${COLOR_GREEN}%s${COLOR_RESET}\n" "$service" "$port" "AVAILABLE"
            return 0
        fi
    else
        printf "  %-20s %-10s ${COLOR_YELLOW}%s${COLOR_RESET}\n" "$service" "$port" "UNKNOWN"
        return 0
    fi
}

export -f network::get_host_ip network::check_port
