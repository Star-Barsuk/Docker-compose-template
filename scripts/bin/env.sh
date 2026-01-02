#!/bin/bash
# =============================================================================
# ENVIRONMENT MANAGEMENT
# =============================================================================

set -euo pipefail

# Initialize paths and source lib.sh
source "$(dirname "$0")/init.sh"

# -----------------------------------------------------------------------------
# CORE FUNCTIONS
# -----------------------------------------------------------------------------
env::get_active() {
    [[ -f "$ACTIVE_ENV_FILE" ]] && head -1 "$ACTIVE_ENV_FILE" 2>/dev/null || echo ""
}

env::get_file() {
    echo "$ENVS_DIR/.env.$1"
}

env::list_files() {
    find "$ENVS_DIR" -maxdepth 1 -name ".env.*" ! -name "*.dist" ! -name "*.example" \
         -type f 2>/dev/null | sort
}

# -----------------------------------------------------------------------------
# LIST ENVIRONMENTS
# -----------------------------------------------------------------------------
env::list() {
    log::header "Available Environments"

    local envs=()
    local active_env
    active_env=$(env::get_active)

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        local name="${file##*/.env.}"
        envs+=("$name")
    done < <(env::list_files)

    if [[ ${#envs[@]} -eq 0 ]]; then
        log::info "No environments found."
        echo ""
        echo "To create your first environment:"
        echo "  cp $ENVS_DIR/.env.example $ENVS_DIR/.env.dev"
        echo "  # Edit $ENVS_DIR/.env.dev with your settings"
        echo "  # Then run 'make env' to select it"
        return 0
    fi

    printf "%-20s %-10s %-10s %s\n" "ENVIRONMENT" "STATUS" "SIZE" "MODIFIED"
    printf "%s\n" "$(printf '=%.0s' {1..70})"

    for env in "${envs[@]}"; do
        local file status color size modified
        file="$(env::get_file "$env")"

        if [[ "$env" == "$active_env" ]]; then
            status="ACTIVE"
            color="$COLOR_GREEN"
        else
            status="INACTIVE"
            color="$COLOR_YELLOW"
        fi

        if [[ -f "$file" ]]; then
            size=$(wc -c < "$file" 2>/dev/null | awk '{printf "%.1fK", $1/1024}' || echo "?")
            modified=$(stat -c "%y" "$file" 2>/dev/null | cut -d' ' -f1 || echo "unknown")
        else
            size="missing"
            modified="N/A"
        fi

        printf "${color}%-20s${COLOR_RESET} %-10s %-10s %s\n" \
            "$env" "$status" "$size" "$modified"
    done

    echo ""
    log::info "Active environment: ${active_env:-none}"
    log::info "Total environments: ${#envs[@]}"
}

# -----------------------------------------------------------------------------
# SELECT ENVIRONMENT
# -----------------------------------------------------------------------------
env::select() {
    local envs=()
    while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        envs+=("${file##*/.env.}")
    done < <(env::list_files)

    if [[ ${#envs[@]} -eq 0 ]]; then
        log::error "No environments found."
        echo ""
        echo "Create one first:"
        echo "  cp $ENVS_DIR/.env.example $ENVS_DIR/.env.dev"
        return 1
    fi

    echo "Select environment:"
    PS3="Enter number (1-${#envs[@]}) or 'q' to cancel: "

    select env in "${envs[@]}"; do
        case $REPLY in
            q|Q)
                log::info "Selection cancelled."
                return 0
                ;;
            [0-9]*)
                if [[ $REPLY -ge 1 ]] && [[ $REPLY -le ${#envs[@]} ]]; then
                    echo "$env" > "$ACTIVE_ENV_FILE"
                    log::success "Active environment set to: $env"

                    if load::environment >/dev/null 2>&1; then
                        log::info "Environment loaded successfully"
                    else
                        log::warn "Environment loaded with warnings"
                    fi
                    return 0
                else
                    echo "Invalid number. Please select 1-${#envs[@]} or 'q' to cancel."
                fi
                ;;
            *)
                echo "Invalid input. Please select 1-${#envs[@]} or 'q' to cancel."
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# SHOW ENVIRONMENT STATUS
# -----------------------------------------------------------------------------
env::status() {
    local env_name
    env_name=$(env::get_active)

    if [[ -z "$env_name" ]]; then
        log::info "No active environment."
        echo "Use 'make env' to select one."
        return 0
    fi

    local env_file
    env_file="$(env::get_file "$env_name")"

    if [[ ! -f "$env_file" ]]; then
        log::error "Environment file not found: $env_file"
        return 1
    fi

    if ! load::environment >/dev/null 2>&1; then
        log::error "Failed to load environment"
        return 1
    fi

    log::header "Environment: $env_name"
    echo "File:    $(relpath "$env_file")"
    echo "Size:    $(wc -c < "$env_file" | awk '{printf "%.1fK", $1/1024}')"
    echo "Modified: $(stat -c "%y" "$env_file" 2>/dev/null | cut -d' ' -f1-2 || echo "unknown")"
    echo ""

    local categories=(
        "PROJECT:^COMPOSE_"
        "APPLICATION:^APP_"
        "DATABASE:^DB_"
        "PGADMIN:^PGADMIN_"
        "SECURITY:_PASSWORD$|_SECRET$|_KEY$|_TOKEN$"
    )

    local all_vars=()
    mapfile -t all_vars < <(compgen -v | grep -E '^[A-Z_][A-Z0-9_]*$' | sort)

    local total_vars=0

    for category in "${categories[@]}"; do
        local cat_name="${category%%:*}"
        local pattern="${category#*:}"
        local vars=()

        for var in "${all_vars[@]}"; do
            [[ "$var" =~ $pattern ]] && vars+=("$var")
        done

        if [[ ${#vars[@]} -gt 0 ]]; then
            echo "=== $cat_name ==="
            for var in "${vars[@]}"; do
                local value="${!var:-}"
                if [[ "$var" =~ _PASSWORD$|_SECRET$|_KEY$|_TOKEN$ ]]; then
                    value="********"
                elif [[ ${#value} -gt 50 ]]; then
                    value="${value:0:47}..."
                fi
                printf "  %-25s = %s\n" "$var" "$value"
                : $((total_vars++))
            done
            echo ""
        fi
    done

    log::info "Total variables loaded: $total_vars"
    return 0
}

# -----------------------------------------------------------------------------
# VALIDATE ENVIRONMENT
# -----------------------------------------------------------------------------
env::validate() {
    local env_name
    env_name=$(env::get_active)

    if [[ -z "$env_name" ]]; then
        log::error "No active environment set."
        return 1
    fi

    local env_file
    env_file="$(env::get_file "$env_name")"

    if [[ ! -f "$env_file" ]]; then
        log::error "File not found: $env_file"
        return 1
    fi

    log::header "Validating: $env_name"

    local perms
    perms=$(stat -c "%a" "$env_file" 2>/dev/null || echo "unknown")

    echo "File:        $(relpath "$env_file")"
    echo "Permissions: $perms"
    echo ""

    if [[ "$perms" != "600" ]] && [[ "$perms" != "644" ]]; then
        log::warn "File permissions $perms (recommended: 600 for sensitive data)"
    fi

    if load::environment >/dev/null 2>&1; then
        log::success "✅ Environment loads successfully"
        return 0
    else
        log::error "❌ Failed to load environment"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# MAIN DISPATCHER
# -----------------------------------------------------------------------------
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        list|select|status|validate)
            env::$cmd "${@:2}"
            ;;
        load)
            # Internal command used by other scripts
            load::environment || exit 1
            ;;
        help|--help|-h)
            cat << EOF
Environment Management

Usage: $0 COMMAND

Commands:
  list      List all available environments
  select    Interactively select environment
  status    Show current environment status
  validate  Validate current environment
  load      Load current environment (internal use)

Examples:
  $0 list
  $0 select
  $0 status
EOF
            ;;
        *)
            log::error "Unknown command: $cmd"
            echo "Use '$0 help' for usage"
            return 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
