#!/bin/bash
# =============================================================================
# ENVIRONMENT MANAGEMENT
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

# --------------------------
# PATH CONSTANTS
# --------------------------
readonly ENVS_DIR="$(root::path)/envs"
readonly ACTIVE_ENV_FILE="$(root::path)/.active-env"
readonly ENV_DIST="$ENVS_DIR/.env.dist"

LOG_LEVEL="${LOG_LEVEL:-INFO}"
CURRENT_ENV=""
SHOW="${SHOW:-all}"
export LC_ALL=C  # Consistent sorting

# -----------------------------------------------------------------------------
# UTILITY FUNCTIONS
# -----------------------------------------------------------------------------
relpath() {
    local path="$1"
    local root
    root="$(root::path)"
    echo "${path#$root/}"
}

simple_file_timestamp() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "unknown"
        return 1
    fi

    # Try ls -l output (works everywhere)
    local timestamp
    timestamp="$(ls -l "$file" 2>/dev/null | head -1)"

    if [[ -n "$timestamp" ]]; then
        # Parse ls -l output format: -rw-r--r-- 1 user group size month day time year filename
        # Example: -rw-r--r-- 1 user group 123 Jan 3 12:30 file.txt
        local month day time_or_year

        # Get the 6th, 7th, and 8th fields from ls -l
        month="$(echo "$timestamp" | awk '{print $6}')"
        day="$(echo "$timestamp" | awk '{print $7}')"
        time_or_year="$(echo "$timestamp" | awk '{print $8}')"

        # Convert month name to number
        local month_num
        case "$month" in
            Jan) month_num="01" ;;
            Feb) month_num="02" ;;
            Mar) month_num="03" ;;
            Apr) month_num="04" ;;
            May) month_num="05" ;;
            Jun) month_num="06" ;;
            Jul) month_num="07" ;;
            Aug) month_num="08" ;;
            Sep) month_num="09" ;;
            Oct) month_num="10" ;;
            Nov) month_num="11" ;;
            Dec) month_num="12" ;;
            *) month_num="00" ;;
        esac

        # Check if time_or_year is a year (4 digits) or time (HH:MM)
        if [[ "$time_or_year" =~ ^[0-9]{4}$ ]]; then
            # It's a year (file older than 6 months)
            echo "${time_or_year}-${month_num}-${day} 00:00:00"
        elif [[ "$time_or_year" =~ ^[0-9]{1,2}:[0-9]{2}$ ]]; then
            # It's a time (file from current year)
            local current_year
            current_year="$(date +%Y 2>/dev/null || echo "2026")"
            echo "${current_year}-${month_num}-${day} ${time_or_year}:00"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# -----------------------------------------------------------------------------
# CORE FUNCTIONS
# -----------------------------------------------------------------------------
env::get_active() {
    if [[ -f "$ACTIVE_ENV_FILE" ]]; then
        local env_name
        read -r env_name < "$ACTIVE_ENV_FILE"
        echo "$env_name"
    fi
}

env::get_file() {
    local env_name="$1"
    echo "$ENVS_DIR/.env.$env_name"
}

# -----------------------------------------------------------------------------
# SAFE ENV LOADING
# -----------------------------------------------------------------------------
env::load() {
    local env_name="$1"

    if [[ "$CURRENT_ENV" == "$env_name" ]]; then
        log::debug "Environment '$env_name' already loaded."
        return 0
    fi

    local env_file
    env_file="$(env::get_file "$env_name")"

    if [[ ! -f "$env_file" ]]; then
        log::error "Environment file not found: $(relpath "$env_file")"
        return 1
    fi

    if [[ ! -r "$env_file" ]]; then
        log::error "Environment file not readable: $(relpath "$env_file")"
        return 1
    fi

    # Clear previous environment variables (except system ones)
    local preserve_vars=(PATH HOME USER LOGNAME SHELL TERM LOG_LEVEL SHOW LC_ALL)
    for var in $(compgen -v | grep -E '^[A-Z_][A-Z0-9_]*$'); do
        if [[ ! " ${preserve_vars[*]} " =~ " ${var} " ]]; then
            unset "$var" 2>/dev/null || true
        fi
    done

    # Load variables safely
    local count=0
    while IFS='=' read -r key value; do
        # Skip comments, empty lines, and malformed entries
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${key//[[:space:]]/}" ]] && continue

        # Clean key
        key="${key%%[[:space:]]*}"
        key="${key##[[:space:]]*}"

        # Validate key format
        if [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            # Clean value (remove quotes and trailing comments)
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            value="${value%%[[:space:]]#*}"
            value="${value%"${value##*[![:space:]]}"}"  # Trim trailing spaces

            # Export safely
            export "$key"="$value"
            ((count++))

            if [[ "$LOG_LEVEL" == "DEBUG" ]]; then
                log::debug "Loaded: $key"
            fi
        else
            log::warn "Skipping invalid variable name in '$env_name': $key"
        fi
    done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$env_file" || true)

    CURRENT_ENV="$env_name"

    if [[ $count -eq 0 ]]; then
        log::warn "No valid variables loaded from '$env_name'"
    else
        log::success "Loaded $count variables from '$env_name'"
    fi
    return 0
}

# -----------------------------------------------------------------------------
# LIST ENVIRONMENTS
# -----------------------------------------------------------------------------
env::list() {
    log::header "Available Environments"

    local envs=()
    while IFS= read -r f; do
        local env_name
        env_name="$(basename "$f" | sed 's|^\.env\.||')"
        envs+=("$env_name")
    done < <(find "$ENVS_DIR" -maxdepth 1 -type f -name ".env.*" ! -name "*.example" ! -name ".env.dist" 2>/dev/null | sort)

    if [[ ${#envs[@]} -eq 0 ]]; then
        log::info "No environments found."
        echo ""
        echo "To create an environment:"
        echo "  1. Copy an example file: cp envs/.env.dev.example envs/.env.dev"
        echo "  2. Edit the new file with your configuration"
        echo "  3. Run 'make env' to select it"
        return 0
    fi

    local active
    active="$(env::get_active || echo "")"

    printf "%-20s %-12s %s\n" "ENVIRONMENT" "STATUS" "LAST MODIFIED"
    printf "%s\n" "$(printf '%.0s-' {1..70})"

    for env in "${envs[@]}"; do
        local env_file status color modified
        env_file="$(env::get_file "$env")"

        # Status
        if [[ "$env" == "$active" ]]; then
            status="ACTIVE"
            color="$COLOR_GREEN"
        else
            status="INACTIVE"
            color="$COLOR_YELLOW"
        fi

        # Get formatted timestamp
        modified="$(simple_file_timestamp "$env_file")"

        printf "${color}%-20s${COLOR_RESET} %-12s %s\n" \
            "$env" "$status" "$modified"
    done

    echo ""
    echo "Active environment: ${active:-none}"
    echo "Current time: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)"
}

# -----------------------------------------------------------------------------
# SELECT ENVIRONMENT
# -----------------------------------------------------------------------------
env::select() {
    local envs=()
    while IFS= read -r f; do
        envs+=("$(basename "$f" | sed 's|^\.env\.||')")
    done < <(find "$ENVS_DIR" -maxdepth 1 -type f -name ".env.*" ! -name "*.example" ! -name ".env.dist" 2>/dev/null | sort)

    if [[ ${#envs[@]} -eq 0 ]]; then
        log::error "No environments found."
        echo ""
        echo "To create your first environment:"
        echo "  cp envs/.env.dev.example envs/.env.dev"
        echo "  # Edit envs/.env.dev with your settings"
        echo "  # Then run 'make env' again"
        return 1
    fi

    echo "Select environment:"
    local i=1
    for env in "${envs[@]}"; do
        local env_file
        env_file="$(env::get_file "$env")"
        local modified
        modified="$(simple_file_timestamp "$env_file")"
        printf "  %2d) %-15s (updated: %s)\n" "$i" "$env" "$modified"
        ((i++))
    done
    echo "  q) Cancel"

    while true; do
        read -rp "#? " choice

        case "$choice" in
            [qQ])
                log::info "Selection cancelled."
                return 0
                ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && \
                   [[ "$choice" -ge 1 ]] && \
                   [[ "$choice" -le ${#envs[@]} ]]; then
                    break
                else
                    echo "Invalid choice. Please enter a number between 1 and ${#envs[@]}, or 'q' to cancel."
                fi
                ;;
        esac
    done

    local selected_env="${envs[$((choice-1))]}"
    local active
    active="$(env::get_active || echo "")"

    if [[ "$active" == "$selected_env" ]]; then
        log::info "Environment '$selected_env' is already active."
        return 0
    fi

    # Save the active environment
    echo "$selected_env" > "$ACTIVE_ENV_FILE"
    log::success "Active environment set to '$selected_env'"

    # Load the environment
    env::load "$selected_env" || {
        log::error "Failed to load environment '$selected_env'"
        return 1
    }
}

# -----------------------------------------------------------------------------
# SHOW ENV STATUS
# -----------------------------------------------------------------------------
env::status() {
    local env_name
    env_name="$(env::get_active)"

    if [[ -z "$env_name" ]]; then
        log::info "No active environment."
        echo "Use 'make env' to select an environment."
        return 0
    fi

    local env_file
    env_file="$(env::get_file "$env_name")"

    if [[ ! -f "$env_file" ]]; then
        log::error "Environment file not found: $(relpath "$env_file")"
        return 1
    fi

    # Load environment
    env::load "$env_name" || return 1

    log::header "Environment Status: $env_name"
    echo "File: $(relpath "$env_file")"
    echo "Modified: $(simple_file_timestamp "$env_file")"
    echo ""

    # Define categories
    declare -A categories=(
        ["DOCKER"]="^COMPOSE_"
        ["APPLICATION"]="^APP_"
        ["DATABASE"]="^DB_"
        ["PGADMIN"]="^PGADMIN_"
        ["HEALTHCHECK"]="^HEALTHCHECK"
        ["POSTGRES"]="^POSTGRES_"
        ["SECURITY"]="_PASSWORD$|_SECRET$|_KEY$|_TOKEN$|SECRET_|PASSWORD_"
    )

    # Track which variables we've displayed
    local displayed_vars=()
    local has_content=false

    # Process each category
    for category in "${!categories[@]}"; do
        local pattern="${categories[$category]}"
        local vars_in_category=()

        # Extract variables for this category
        while IFS= read -r line; do
            local var="${line%%=*}"

            # Skip if already displayed
            if [[ " ${displayed_vars[*]} " =~ " $var " ]]; then
                continue
            fi

            # Check if variable matches category pattern
            if [[ "$var" =~ $pattern ]]; then
                vars_in_category+=("$var")
                displayed_vars+=("$var")
            fi
        done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$env_file" 2>/dev/null || true)

        # Sort and display
        if [[ ${#vars_in_category[@]} -gt 0 ]]; then
            has_content=true
            echo "=== $category ==="

            IFS=$'\n' vars_in_category=($(sort <<<"${vars_in_category[*]}"))
            unset IFS

            for var in "${vars_in_category[@]}"; do
                local value="${!var:-<unset>}"

                # Mask sensitive values
                if [[ "$category" == "SECURITY" ]] || \
                   [[ "$var" =~ _PASSWORD$|_SECRET$|_KEY$|_TOKEN$ ]]; then
                    value="********"
                elif [[ ${#value} -gt 50 ]]; then
                    value="${value:0:47}..."
                fi

                if [[ "$value" == "<unset>" ]]; then
                    printf "  %-30s = ${COLOR_RED}%s${COLOR_RESET}\n" "$var" "$value"
                else
                    printf "  %-30s = ${COLOR_GREEN}%s${COLOR_RESET}\n" "$var" "$value"
                fi
            done
            echo ""
        fi
    done

    # Show remaining variables in "OTHER" category
    local other_vars=()
    while IFS= read -r line; do
        local var="${line%%=*}"
        if [[ ! " ${displayed_vars[*]} " =~ " $var " ]]; then
            other_vars+=("$var")
        fi
    done < <(grep -E '^[A-Z_][A-Z0-9_]*=' "$env_file" 2>/dev/null || true)

    if [[ ${#other_vars[@]} -gt 0 ]]; then
        has_content=true
        echo "=== OTHER ==="

        IFS=$'\n' other_vars=($(sort <<<"${other_vars[*]}"))
        unset IFS

        for var in "${other_vars[@]}"; do
            local value="${!var:-<unset>}"
            printf "  %-30s = ${COLOR_CYAN}%s${COLOR_RESET}\n" "$var" "$value"
        done
        echo ""
    fi

    if [[ "$has_content" == "false" ]]; then
        log::warn "No environment variables found in file."
    fi

    echo "Total variables loaded: ${#displayed_vars[@]}"
    echo "Last modified: $(simple_file_timestamp "$env_file")"
}

# -----------------------------------------------------------------------------
# VALIDATE ENVIRONMENT
# -----------------------------------------------------------------------------
env::validate() {
    local env_name
    env_name="$(env::get_active || echo "")"

    if [[ -z "$env_name" ]]; then
        log::info "No active environment set."
        echo "Use 'make env' to select an environment first."
        return 0
    fi

    local env_file
    env_file="$(env::get_file "$env_name")"

    if [[ ! -f "$env_file" ]]; then
        log::error "Environment file not found: $(relpath "$env_file")"
        return 1
    fi

    # Load environment
    env::load "$env_name" || return 1

    log::header "Validating Environment: $env_name"
    echo "File: $(relpath "$env_file")"
    echo "Modified: $(simple_file_timestamp "$env_file")"
    echo ""

    local env_vars=() dist_vars=()
    local total_vars=0 unknown_vars=0 missing_vars=0 placeholder_vars=0

    # Extract variables from environment file
    while IFS= read -r line; do
        if [[ "$line" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
            local var="${line%%=*}"
            local value="${line#*=}"
            env_vars+=("$var")

            # Check for placeholder values
            if [[ "$value" =~ changeme|yourdomain|example\.com|TODO|FIXME|YOUR_ ]]; then
                ((placeholder_vars++))
            fi
        fi
    done < "$env_file"

    total_vars=${#env_vars[@]}

    # Check if .env.dist exists
    if [[ ! -f "$ENV_DIST" ]]; then
        log::warn "Template file '.env.dist' not found."
        echo "Cannot validate against template. Variables will not be checked."
    else
        # Extract variables from template
        while IFS= read -r line; do
            [[ "$line" =~ ^[A-Z_][A-Z0-9_]*= ]] && dist_vars+=("${line%%=*}")
        done < "$ENV_DIST"

        # Find unknown variables (in env but not in dist)
        for var in "${env_vars[@]}"; do
            if [[ ! " ${dist_vars[*]} " =~ " ${var} " ]]; then
                ((unknown_vars++))
            fi
        done

        # Find missing variables (in dist but not in env)
        for var in "${dist_vars[@]}"; do
            if [[ ! " ${env_vars[*]} " =~ " ${var} " ]]; then
                ((missing_vars++))
            fi
        done
    fi

    # Display results
    echo "=== VALIDATION RESULTS ==="
    printf "Total variables:        %3d\n" "$total_vars"

    if [[ -f "$ENV_DIST" ]]; then
        printf "Variables in template:  %3d\n" "${#dist_vars[@]}"
        printf "Unknown variables:      %3d\n" "$unknown_vars"
        printf "Missing variables:      %3d\n" "$missing_vars"
    fi

    printf "Placeholder values:     %3d\n" "$placeholder_vars"
    echo ""

    # Detailed warnings
    if [[ $placeholder_vars -gt 0 ]]; then
        log::warn "Found $placeholder_vars variable(s) with placeholder values:"
        grep -E 'changeme|yourdomain|example\.com|TODO|FIXME|YOUR_' "$env_file" 2>/dev/null | \
        while IFS= read -r line; do
            echo "  - ${line%%=*}"
        done
        echo ""
    fi

    if [[ -f "$ENV_DIST" ]] && [[ $unknown_vars -gt 0 ]]; then
        log::info "Unknown variables (${unknown_vars} found - not in template):"
        for var in "${env_vars[@]}"; do
            if [[ ! " ${dist_vars[*]} " =~ " ${var} " ]]; then
                echo "  - $var"
            fi
        done | head -10
        [[ $unknown_vars -gt 10 ]] && echo "  ... and $((unknown_vars - 10)) more"
        echo ""
    fi

    if [[ -f "$ENV_DIST" ]] && [[ $missing_vars -gt 0 ]]; then
        log::info "Missing variables (${missing_vars} found - in template but not set):"
        for var in "${dist_vars[@]}"; do
            if [[ ! " ${env_vars[*]} " =~ " ${var} " ]]; then
                echo "  - $var"
            fi
        done | head -10
        [[ $missing_vars -gt 10 ]] && echo "  ... and $((missing_vars - 10)) more"
        echo ""
    fi

    # Overall status
    local has_issues=false

    if [[ $placeholder_vars -gt 0 ]]; then
        log::warn "⚠️  Found placeholder values that should be replaced."
        has_issues=true
    fi

    if [[ -f "$ENV_DIST" ]] && [[ $unknown_vars -gt 0 ]]; then
        log::info "ℹ️  Some variables are not in the template (may be environment-specific)."
        has_issues=true
    fi

    if [[ -f "$ENV_DIST" ]] && [[ $missing_vars -gt 0 ]]; then
        log::info "ℹ️  Some template variables are not set (may be optional)."
        has_issues=true
    fi

    if [[ "$has_issues" == "false" ]]; then
        if [[ -f "$ENV_DIST" ]]; then
            log::success "✅ All variables are valid and match the template."
        else
            log::success "✅ Environment loaded successfully."
        fi
    else
        log::info "✓ Validation completed. Review warnings above."
    fi

    return 0
}

# -----------------------------------------------------------------------------
# MAIN DISPATCHER
# -----------------------------------------------------------------------------
main() {
    local command="${1:-help}"

    case "$command" in
        list)
            env::list
            ;;
        select)
            env::select
            ;;
        status)
            env::status
            ;;
        validate)
            env::validate
            ;;
        help|--help|-h)
            echo "Environment Management Tool"
            echo "Usage: $0 {list|select|status|validate|help}"
            echo ""
            echo "Commands:"
            echo "  list     - List available environments"
            echo "  select   - Interactively select environment"
            echo "  status   - Show current environment status"
            echo "  validate - Validate current environment"
            echo "  help     - Show this help"
            echo ""
            echo "Environment variables:"
            echo "  LOG_LEVEL - Set log level (DEBUG, INFO, WARN, ERROR)"
            echo "  SHOW      - Control status output (all, set, unset)"
            ;;
        *)
            log::error "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            return 1
            ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
