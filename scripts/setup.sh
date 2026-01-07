#!/bin/bash
# =============================================================================
# PROJECT SETUP SCRIPT
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
    COLOR_BOLD=$'\033[1m'
else
    COLOR_RESET=''; COLOR_RED=''; COLOR_GREEN=''; COLOR_YELLOW=''
    COLOR_BLUE=''; COLOR_CYAN=''; COLOR_BOLD=''
fi

log::header()   { printf "${COLOR_CYAN}==>${COLOR_RESET} ${COLOR_BOLD}%s${COLOR_RESET}\n" "$1"; }
log::info()     { printf "${COLOR_BLUE}[INFO]${COLOR_RESET} %s\n" "$1"; }
log::success()  { printf "${COLOR_GREEN}[OK]${COLOR_RESET} %s\n" "$1"; }
log::warn()     { printf "${COLOR_YELLOW}[WARN]${COLOR_RESET} %s\n" "$1" >&2; }
log::error()    { printf "${COLOR_RED}[ERROR]${COLOR_RESET} %s\n" "$1" >&2; }

find_example_envs() {
    find . -name ".env.*.example" -type f 2>/dev/null | \
        grep -v node_modules | grep -v .git | sort
}

remove_example_suffix() {
    local filename="$1"
    echo "${filename%.example}"
}

# -----------------------------------------------------------------------------
# MAIN SCRIPT
# -----------------------------------------------------------------------------
main() {
    log::header "PROJECT SETUP SCRIPT"
    echo "This script will:"
    echo "  1. Set execute permissions for all scripts"
    echo "  2. Convert .env.*.example files to regular .env.* files"
    echo ""

    # Step 1: Set execute permissions
    log::header "Step 1: Setting execute permissions for scripts"

    local scripts=(
        "scripts/bin/app.sh"
        "scripts/bin/docker.sh"
        "scripts/bin/env.sh"
        "scripts/bin/init.sh"
        "scripts/bin/lib.sh"
        "scripts/bin/secrets.sh"
        "scripts/entrypoint.app.sh"
    )

    local changed_perms=0
    for script in "${scripts[@]}"; do
        if [[ -f "$script" ]]; then
            if [[ ! -x "$script" ]]; then
                chmod +x "$script"
                log::info "Made executable: $script"
                changed_perms=$((changed_perms + 1))
            else
                log::info "Already executable: $script"
            fi
        else
            log::warn "Script not found: $script"
        fi
    done

    log::success "Permissions updated for $changed_perms scripts"
    echo ""

    # Step 2: Convert .env.*.example files
    log::header "Step 2: Converting .env.*.example files"

    local example_files=()
    mapfile -t example_files < <(find_example_envs)

    if [[ ${#example_files[@]} -eq 0 ]]; then
        log::warn "No .env.*.example files found in the project"
        echo ""

        local env_files=()
        mapfile -t env_files < <(find . -name ".env.*" ! -name "*.example" -type f 2>/dev/null | \
            grep -v node_modules | grep -v .git | sort)

        if [[ ${#env_files[@]} -eq 0 ]]; then
            log::info "No environment files found. Creating basic structure..."

            mkdir -p envs

            cat > ".env.dev.example" << 'EOF'
# Project settings
COMPOSE_PROJECT_NAME=myproject
APP_VERSION=1.0.0

# Application settings
APP_PORT_DEV=8000
APP_PORT_PROD=8080

# Database settings
DB_HOST=db
DB_PORT=5432
DB_NAME=appdb
DB_USER=appuser
# DB_PASSWORD will be set from secrets

# PgAdmin settings
PGADMIN_PORT_DEV=5050
PGADMIN_EMAIL=admin@example.com
# PGADMIN_PASSWORD will be set from secrets

# Docker Compose
COMPOSE_PROFILES=dev
EOF

            log::info "Created .env.dev.example"
            example_files=(".env.dev.example")
        else
            log::info "Found existing environment files:"
            for env_file in "${env_files[@]}"; do
                log::info "  $(basename "$env_file")"
            done
        fi
    fi

    local converted=0
    local skipped=0

    for example_file in "${example_files[@]}"; do
        local target_file
        target_file=$(remove_example_suffix "$example_file")

        if [[ -f "$target_file" ]]; then
            log::info "Skipping: $target_file already exists"
            skipped=$((skipped + 1))
            continue
        fi

        cp "$example_file" "$target_file"

        if [[ "$(dirname "$target_file")" == "." ]]; then
            mkdir -p envs
            local base_name
            base_name=$(basename "$target_file")
            mv "$target_file" "envs/$base_name"
            target_file="envs/$base_name"
            log::info "Moved $base_name to envs/ directory"
        fi

        log::info "Created: $target_file"
        converted=$((converted + 1))
    done

    if [[ $converted -gt 0 ]]; then
        log::success "Converted $converted .env.*.example files"
    fi

    if [[ $skipped -gt 0 ]]; then
        log::info "Skipped $skipped files (already exist)"
    fi

    # Step 3: Set default active environment
	echo ""
    log::header "Step 3: Setting up default environment"

    if [[ -f ".active-env" ]]; then
        local active_env
        active_env=$(head -1 ".active-env" 2>/dev/null || echo "")
        log::info "Active environment is: ${active_env:-not set}"
    else
        local env_files=()
        mapfile -t env_files < <(find envs -name ".env.*" ! -name "*.example" -type f 2>/dev/null 2>/dev/null | sort)

        if [[ ${#env_files[@]} -gt 0 ]]; then
            local first_env_file="${env_files[0]}"
            local first_env="${first_env_file##*/.env.}"

            echo "$first_env" > .active-env
            log::info "Set active environment to: $first_env"
        else
            mapfile -t root_envs < <(find . -maxdepth 1 -name ".env.*" ! -name "*.example" -type f 2>/dev/null | sort)

            if [[ ${#root_envs[@]} -gt 0 ]]; then
                local first_env_file="${root_envs[0]}"
                local first_env="${first_env_file##*/.env.}"

                echo "$first_env" > .active-env
                log::info "Set active environment to: $first_env"

                echo ""
                log::warn "Environment files are in project root"
                echo "Consider moving them to envs/ directory:"
                echo "  mkdir -p envs"
                echo "  mv .env.* envs/"
            else
                echo "dev" > .active-env
                log::info "Created .active-env with 'dev'"

                if [[ ! -f "envs/.env.dev" ]] && [[ ! -f ".env.dev" ]]; then
                    mkdir -p envs
                    cat > "envs/.env.dev" << 'EOF'
# Project settings
COMPOSE_PROJECT_NAME=myproject
APP_VERSION=1.0.0

# Application settings
APP_PORT_DEV=8000
APP_PORT_PROD=8080

# Database settings
DB_HOST=db
DB_PORT=5432
DB_NAME=appdb
DB_USER=appuser
# DB_PASSWORD will be set from secrets

# PgAdmin settings
PGADMIN_PORT_DEV=5050
PGADMIN_EMAIL=admin@example.com
# PGADMIN_PASSWORD will be set from secrets

# Docker Compose
COMPOSE_PROFILES=dev
EOF
                    log::info "Created envs/.env.dev"
                fi
            fi
        fi
    fi

    echo ""
    log::header "SETUP COMPLETE"
    echo ""
}

# Run the main function
main "$@"
