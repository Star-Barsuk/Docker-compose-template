#!/bin/bash
# =============================================================================
# ENVIRONMENT MANAGEMENT WITH LOG_LEVEL
# =============================================================================

source "$(dirname "$0")/lib.sh"

ENVS_DIR="$(root::path)/envs"
ACTIVE_ENV_FILE="$(root::path)/.active-env"
ENV_DIST="$ENVS_DIR/.env.dist"

LOG_LEVEL="${LOG_LEVEL:-INFO}"  # default level

# ----------------------------
# Environment helpers
# ----------------------------
env::get_active() {
    [[ -f "$ACTIVE_ENV_FILE" ]] && cat "$ACTIVE_ENV_FILE" | tr -d '\r\n'
}

env::get_file() {
    local env_name="$1"
    echo "$ENVS_DIR/.env.$env_name"
}

env::load() {
    local env_name="$1"
    local env_file
    env_file="$(env::get_file "$env_name")"

    if [[ ! -f "$env_file" ]]; then
        log::error "Environment file not found: $env_file"
        return 1
    fi

    set -o allexport
    source "$env_file"
    set +o allexport

    local count
    count=$(grep -E '^[A-Z_][A-Z0-9_]*=' "$env_file" | wc -l | tr -d ' ')
    log::info "Loaded $count variables from '$env_name'"
}

env::list() {
    log::header "Available environments"
    local envs=($(ls "$ENVS_DIR"/.env.* 2>/dev/null | grep -vE '\.example$|\.dist$' | sed 's|.*/.env.||'))

    if [[ ${#envs[@]} -eq 0 ]]; then
        log::warn "No environments found"
        return 0
    fi

    for env in "${envs[@]}"; do
        local active_marker=""
        [[ "$env" == "$(env::get_active)" ]] && active_marker="${COLOR_GREEN}✓${COLOR_RESET}"
        printf "  %-15s %s\n" "$env" "$active_marker"
    done
}

env::select() {
    local envs=($(ls "$ENVS_DIR"/.env.* 2>/dev/null | grep -vE '\.example$|\.dist$' | sed 's|.*/.env.||'))
    if [[ ${#envs[@]} -eq 0 ]]; then
        log::error "No environments found"
        return 1
    fi

    echo "Select environment:"
    local i=1
    for env in "${envs[@]}"; do
        printf "  %2d) %s\n" "$i" "$env"
        ((i++))
    done

    read -rp "#? " choice
    local selected_env="${envs[0]}"
    [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#envs[@]} ]] && selected_env="${envs[$((choice-1))]}"

    echo "$selected_env" > "$ACTIVE_ENV_FILE"
    log::success "Active environment set to '$selected_env'"

    env::load "$selected_env" || log::warn "Failed to load environment variables"
}

env::status() {
    local env_name
    env_name="$(env::get_active)"
    if [[ -z "$env_name" ]]; then
        log::warn "No active environment"
        return 0
    fi

    local env_file
    env_file="$(env::get_file "$env_name")"
    if [[ ! -f "$env_file" ]]; then
        log::error "Environment file not found: $env_file"
        return 1
    fi

    set -o allexport
    source "$env_file"
    set +o allexport

    log::header "Environment status: $env_name"

    mapfile -t dist_vars < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$ENV_DIST" | cut -d= -f1 | sort)

    for var in "${dist_vars[@]}"; do
        printf "%-30s = %s\n" "$var" "${!var:-<unset>}"
    done
}

env::validate() {
    local env_name
    env_name="$(env::get_active)"
    if [[ -z "$env_name" ]]; then
        log::warn "No active environment"
        return 0
    fi

    local env_file
    env_file="$(env::get_file "$env_name")"
    if [[ ! -f "$env_file" ]]; then
        log::error "Environment file not found: $env_file"
        return 1
    fi
    [[ ! -f "$ENV_DIST" ]] && log::warn "Dist file not found: $ENV_DIST"

    log::header "Validating environment: $env_name"

    mapfile -t env_vars  < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$env_file" | cut -d= -f1 | sort)
    mapfile -t dist_vars < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$ENV_DIST" | cut -d= -f1 | sort)

    # Unknown vars (в env, которых нет в dist)
    unknown=($(comm -23 <(printf "%s\n" "${env_vars[@]}") <(printf "%s\n" "${dist_vars[@]}")))
    [[ ${#unknown[@]} -gt 0 ]] && { log::warn "Unknown variables:"; printf "  %s\n" "${unknown[@]}"; }

    # Missing vars (в dist, которых нет в env)
    missing=($(comm -13 <(printf "%s\n" "${env_vars[@]}") <(printf "%s\n" "${dist_vars[@]}")))
    [[ ${#missing[@]} -gt 0 ]] && { log::warn "Missing variables:"; printf "  %s\n" "${missing[@]}"; }

    log::success "Environment validation completed"
}

# ----------------------------
# MAIN
# ----------------------------
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
