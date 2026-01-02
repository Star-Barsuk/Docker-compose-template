#!/bin/bash
# =============================================================================
# ENVIRONMENT MANAGEMENT (RELATIVE PATHS + OPTIMIZED)
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

# --------------------------
# PATH CONSTANTS
# --------------------------
ENVS_DIR="$(root::path)/envs"
ACTIVE_ENV_FILE="$(root::path)/.active-env"
ENV_DIST="$ENVS_DIR/.env.dist"

LOG_LEVEL="${LOG_LEVEL:-INFO}"  # default level
CURRENT_ENV=""
SHOW="${SHOW:-all}"             # all | set | unset

# -----------------------------------------------------------------------------
# UTILITIES
# -----------------------------------------------------------------------------
relpath() {
    # Получить путь относительно корня проекта
    local path="$1"
    local root
    root="$(root::path)"
    echo "${path#$root/}"
}

# -----------------------------------------------------------------------------
# GET ACTIVE ENV
# -----------------------------------------------------------------------------
env::get_active() {
    [[ -f "$ACTIVE_ENV_FILE" ]] && read -r env_name < "$ACTIVE_ENV_FILE" && echo "$env_name"
}

# -----------------------------------------------------------------------------
# GET ENV FILE
# -----------------------------------------------------------------------------
env::get_file() {
    local env_name="$1"
    echo "$ENVS_DIR/.env.$env_name"
}

# -----------------------------------------------------------------------------
# LOAD ENV
# -----------------------------------------------------------------------------
env::load() {
    local env_name="$1"
    if [[ "$CURRENT_ENV" == "$env_name" ]]; then
        log::debug "Environment '$env_name' already loaded, skipping."
        return 0
    fi

    local env_file
    env_file="$(env::get_file "$env_name")"
    [[ ! -f "$env_file" ]] && log::warn "Environment file not found: $(relpath "$env_file")" && return 1

    set -o allexport
    source "$env_file"
    set +o allexport

    CURRENT_ENV="$env_name"

    local count
    count=$(grep -E '^[A-Z_][A-Z0-9_]*=' "$env_file" | wc -l | tr -d ' ')
    log::success "Loaded $count variables from '$env_name'"
}

# -----------------------------------------------------------------------------
# LIST ENVIRONMENTS
# -----------------------------------------------------------------------------
env::list() {
    log::header "Available environments"

    local envs=()
    while IFS= read -r f; do
        envs+=("$(basename "$f" | sed 's|.env.||')")
    done < <(find "$ENVS_DIR" -maxdepth 1 -type f -name ".env.*" ! -name "*.example" ! -name ".env.dist")

    [[ ${#envs[@]} -eq 0 ]] && log::info "No environments found" && return

    local active
    active="$(env::get_active || true)"

    for env in "${envs[@]}"; do
        if [[ "$env" == "$active" ]]; then
            printf "%-30s = ${COLOR_GREEN}%-20s${COLOR_RESET}\n" "$env" "active"
        else
            printf "%-30s = ${COLOR_RED}%-20s${COLOR_RESET}\n" "$env" "inactive"
        fi
    done
}

# -----------------------------------------------------------------------------
# SELECT ENVIRONMENT
# -----------------------------------------------------------------------------
env::select() {
    local envs=()
    while IFS= read -r f; do
        envs+=("$(basename "$f" | sed 's|.env.||')")
    done < <(find "$ENVS_DIR" -maxdepth 1 -type f -name ".env.*" ! -name "*.example" ! -name ".env.dist")

    [[ ${#envs[@]} -eq 0 ]] && log::fatal "No environments found"

    echo "Select environment:"
    local i=1
    for env in "${envs[@]}"; do
        printf "  %2d) %s\n" "$i" "$env"
        ((i++))
    done

    read -rp "#? " choice
    local selected_env="${envs[0]}"
    [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#envs[@]} ]] && selected_env="${envs[$((choice-1))]}"

    local active
    active="$(env::get_active || true)"

    if [[ "$active" == "$selected_env" ]]; then
        log::info "Environment '$selected_env' is already active."
    else
        echo "$selected_env" > "$ACTIVE_ENV_FILE"
        log::success "Active environment set to '$selected_env'"
        env::load "$selected_env" || true
    fi
}

# -----------------------------------------------------------------------------
# SHOW ENV STATUS
# -----------------------------------------------------------------------------
env::status() {
    local env_name
    env_name="$(env::get_active)"
    [[ -z "$env_name" ]] && log::info "No active environment" && return 0

    env::load "$env_name" || return

    log::header "Environment status: $env_name (SHOW=${SHOW})"

    mapfile -t dist_vars < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$ENV_DIST" | cut -d= -f1 | sort)

    for var in "${dist_vars[@]}"; do
        local val="${!var:-<unset>}"
        case "$SHOW" in
            set)   [[ "$val" == "<unset>" ]] && continue ;;
            unset) [[ "$val" != "<unset>" ]] && continue ;;
        esac
        if [[ "$val" == "<unset>" ]]; then
            printf "%-30s = ${COLOR_RED}%-20s${COLOR_RESET}\n" "$var" "$val"
        else
            printf "%-30s = ${COLOR_GREEN}%-20s${COLOR_RESET}\n" "$var" "$val"
        fi
    done
}

# -----------------------------------------------------------------------------
# VALIDATE ENV
# -----------------------------------------------------------------------------
env::validate() {
    local env_name
    env_name="$(env::get_active || true)"

    if [[ -z "$env_name" ]]; then
        log::info "No active environment set, skipping validation."
        return 0
    fi

    local env_file
    env_file="$(env::get_file "$env_name")"

    if [[ ! -f "$env_file" ]]; then
        log::warn "Environment file not found: $(relpath "$env_file")"
        return 0
    fi

    # Load environment
    env::load "$env_name" || return

    [[ ! -f "$ENV_DIST" ]] && log::warn "Dist file not found: $(relpath "$ENV_DIST")"

    log::header "Validating environment: $env_name"

    mapfile -t env_vars  < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$env_file" | cut -d= -f1 | sort)
    mapfile -t dist_vars < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$ENV_DIST" | cut -d= -f1 | sort)

    local unknown=($(comm -23 <(printf "%s\n" "${env_vars[@]}") <(printf "%s\n" "${dist_vars[@]}")))
    local missing=($(comm -13 <(printf "%s\n" "${env_vars[@]}") <(printf "%s\n" "${dist_vars[@]}")))

    log::success "Environment validation completed"

    # Unknown → warn
    if [[ ${#unknown[@]} -gt 0 ]]; then
        log::warn "Unknown variables in environment (ignored in processing):"
        for v in "${unknown[@]}"; do printf "  %s\n" "$v"; done
    fi

    # Missing → debug
    if [[ ${#missing[@]} -gt 0 ]]; then
        log::debug "Missing variables (defined in dist, absent in env):"
        for v in "${missing[@]}"; do printf "  %s\n" "$v"; done
    fi

    # Show full environment
    local old_show="$SHOW"
    SHOW=all env::status
    SHOW="$old_show"
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    case "${1:-}" in
        list)     env::list ;;
        select)   env::select ;;
        status)   env::status ;;
        validate) env::validate ;;
        *) log::info "Usage: $0 {list|select|status|validate}" ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
