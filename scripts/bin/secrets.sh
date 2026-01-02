#!/bin/bash
# =============================================================================
# SECRETS MANAGEMENT SCRIPT
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

# -----------------------------------------------------------------------------
# UTILITY FUNCTIONS
# -----------------------------------------------------------------------------

# Simple way to get file permissions (octal)
get_file_perms() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "unknown"
        return 1
    fi

    # Use stat if available
    if command -v stat >/dev/null 2>&1; then
        stat -c "%a" "$file" 2>/dev/null || echo "unknown"
        return 0
    fi

    # Fallback to ls -l
    local ls_output
    ls_output=$(ls -l "$file" 2>/dev/null | awk '{print $1}')

    if [[ -n "$ls_output" ]]; then
        local perm_str="$ls_output"
        local owner=0 group=0 other=0

        # Owner permissions
        [[ ${perm_str:1:1} == "r" ]] && owner=$((owner + 4))
        [[ ${perm_str:2:1} == "w" ]] && owner=$((owner + 2))
        [[ ${perm_str:3:1} == "x" ]] && owner=$((owner + 1))
        [[ ${perm_str:3:1} == "s" ]] && owner=$((owner + 1))
        [[ ${perm_str:3:1} == "S" ]] && owner=$((owner + 1))

        # Group permissions
        [[ ${perm_str:4:1} == "r" ]] && group=$((group + 4))
        [[ ${perm_str:5:1} == "w" ]] && group=$((group + 2))
        [[ ${perm_str:6:1} == "x" ]] && group=$((group + 1))
        [[ ${perm_str:6:1} == "s" ]] && group=$((group + 1))
        [[ ${perm_str:6:1} == "S" ]] && group=$((group + 1))

        # Other permissions
        [[ ${perm_str:7:1} == "r" ]] && other=$((other + 4))
        [[ ${perm_str:8:1} == "w" ]] && other=$((other + 2))
        [[ ${perm_str:9:1} == "x" ]] && other=$((other + 1))
        [[ ${perm_str:9:1} == "t" ]] && other=$((other + 1))
        [[ ${perm_str:9:1} == "T" ]] && other=$((other + 1))

        printf "%d%d%d\n" "$owner" "$group" "$other"
        return 0
    fi

    echo "unknown"
    return 1
}

# Simple way to get file modification time
get_file_mtime() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        echo "unknown"
        return 1
    fi

    # Try different date formats
    date -r "$file" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || \
    ls -l --time-style="+%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null | awk 'NR==1 {print $6, $7}' || \
    echo "unknown"
}

# -----------------------------------------------------------------------------
# SECRETS VALIDATION
# -----------------------------------------------------------------------------

secrets::check() {
    log::header "Validating Secrets"

    validate::directory_exists "$SECRETS_DIR" || return 1

    local has_errors=0
    local has_warnings=0
    local secret_files=()

    # Find all secret files (excluding .example files)
    while IFS= read -r file; do
        if [[ "$(basename "$file")" != *".example.txt" ]]; then
            secret_files+=("$file")
        fi
    done < <(find "$SECRETS_DIR" -type f -name "*.txt" 2>/dev/null | sort)

    if [[ ${#secret_files[@]} -eq 0 ]]; then
        log::warn "No secret files found in $SECRETS_DIR"
        echo ""
        echo "To create secrets:"
        echo "  make secrets-generate"
        return 0
    fi

    log::info "Found ${#secret_files[@]} secret file(s)"
    echo ""

    # Check each secret file
    for file in "${secret_files[@]}"; do
        local filename
        filename=$(basename "$file")
        local status="OK"
        local message=""

        # Check file permissions
        local perms
        perms=$(get_file_perms "$file")

        if [[ "$perms" == "644" ]] || [[ "$perms" == "664" ]] || [[ "$perms" == "666" ]]; then
            status="ERROR"
            message="Insecure permissions: $perms (should be 600 or 400)"
            ((has_errors++))
        elif [[ "$perms" != "600" ]] && [[ "$perms" != "400" ]] && [[ "$perms" != "unknown" ]]; then
            status="WARN"
            message="Unexpected permissions: $perms (should be 600 or 400)"
            ((has_warnings++))
        elif [[ "$perms" == "unknown" ]]; then
            status="WARN"
            message="Cannot determine permissions"
            ((has_warnings++))
        fi

        # Check file size
        local size
        size=$(wc -c < "$file" 2>/dev/null | tr -d ' ' || echo "0")
        if [[ $size -lt 32 ]]; then
            if [[ "$status" == "OK" ]]; then
                status="WARN"
            fi
            message="${message:+$message; }Secret may be too short: $size bytes"
            ((has_warnings++))
        fi

        # Check if file is empty
        if [[ $size -eq 0 ]]; then
            status="ERROR"
            message="Empty secret file"
            ((has_errors++))
        fi

        # Check for common weak secrets
        local content
        content=$(head -1 "$file" 2>/dev/null | tr -d '\r\n' || echo "")
        if [[ "$content" == "password" ]] || [[ "$content" == "changeme" ]] || \
           [[ "$content" == "secret" ]] || [[ "$content" == "admin" ]] || \
           [[ "$content" == "123456" ]] || [[ "$content" == "test" ]]; then
            status="ERROR"
            message="Weak/obvious secret detected"
            ((has_errors++))
        fi

        # Check for placeholder/example values
        if [[ "$filename" == *".example"* ]] || [[ "$content" == *"example"* ]] || \
           [[ "$content" == *"changeme"* ]] || [[ "$content" == *"TODO"* ]]; then
            if [[ "$status" != "ERROR" ]]; then
                status="WARN"
                message="Example/placeholder secret detected"
                ((has_warnings++))
            fi
        fi

        # Print status
        case "$status" in
            OK)
                printf "${COLOR_GREEN}✓${COLOR_RESET} %-30s %s\n" "$filename" "$message"
                ;;
            WARN)
                printf "${COLOR_YELLOW}⚠${COLOR_RESET} %-30s ${COLOR_YELLOW}%s${COLOR_RESET}\n" "$filename" "$message"
                ;;
            ERROR)
                printf "${COLOR_RED}✗${COLOR_RESET} %-30s ${COLOR_RED}%s${COLOR_RESET}\n" "$filename" "$message"
                ;;
        esac
    done

    echo ""

    if [[ $has_errors -gt 0 ]]; then
        log::error "Found $has_errors critical issue(s) with secrets"
        echo "Recommended actions:"
        echo "  1. Regenerate weak secrets: make secrets-generate"
        echo "  2. Fix permissions: chmod 600 docker/secrets/*.txt"
        echo "  3. Review and update secrets as needed"
        return 1
    elif [[ $has_warnings -gt 0 ]]; then
        log::warn "Found $has_warnings warning(s) with secrets"
        echo "Consider regenerating secrets: make secrets-generate"
        return 0
    else
        log::success "All secrets validated successfully"
        return 0
    fi
}

# -----------------------------------------------------------------------------
# SECRETS LISTING
# -----------------------------------------------------------------------------

secrets::list() {
    log::header "Listing Secrets"

    validate::directory_exists "$SECRETS_DIR" || return 1

    local secret_files=()

    while IFS= read -r file; do
        secret_files+=("$(basename "$file")")
    done < <(find "$SECRETS_DIR" -type f -name "*.txt" 2>/dev/null | sort)

    if [[ ${#secret_files[@]} -eq 0 ]]; then
        log::info "No secret files found"
        echo ""
        echo "To create secrets:"
        echo "  make secrets-generate"
        return 0
    fi

    printf "%-35s %-10s %-12s %s\n" "FILENAME" "SIZE" "PERMISSIONS" "LAST MODIFIED"
    printf "%s\n" "$(printf '%.0s-' {1..80})"

    for filename in "${secret_files[@]}"; do
        local file="$SECRETS_DIR/$filename"
        local size perms modified

        size=$(wc -c < "$file" 2>/dev/null | tr -d ' ' || echo "0")
        if [[ $size -ge 1024 ]]; then
            size="$((size / 1024))KB"
        else
            size="${size}B"
        fi

        perms=$(get_file_perms "$file")
        modified=$(get_file_mtime "$file")

        if [[ "$perms" == "600" ]] || [[ "$perms" == "400" ]]; then
            perms="${COLOR_GREEN}$perms${COLOR_RESET}"
        elif [[ "$perms" == "unknown" ]]; then
            perms="${COLOR_YELLOW}$perms${COLOR_RESET}"
        else
            perms="${COLOR_RED}$perms${COLOR_RESET}"
        fi

        printf "%-35s %-10s %-12s %s\n" "$filename" "$size" "$perms" "$modified"
    done

    echo ""
    log::info "Total secrets: ${#secret_files[@]}"
    log::info "Location: $(relpath "$SECRETS_DIR")"

    local env_name
    if env_name="$(load::environment 2>/dev/null)"; then
        echo ""
        log::info "Active environment: $env_name"
        local env_file
        env_file="$(root::path)/envs/.env.$env_name"
        if [[ -f "$env_file" ]]; then
            log::info "Secret references in environment file:"
            grep -i "secret\|password\|key\|token" "$env_file" 2>/dev/null | \
                grep -v "^#" | \
                sed 's/^/  /' || log::info "  None found"
        fi
    else
        log::warn "No active environment set. Run 'make env' first."
    fi

    echo ""
    log::warn "SECURITY NOTES:"
    echo "  • Never commit actual secret files to version control!"
    echo "  • Keep .example.txt files for reference only"
    echo "  • Add 'docker/secrets/*.txt' to .gitignore (except .example.txt)"
    echo "  • Use different secrets for different environments"
    echo "  • Rotate secrets periodically in production"
}

# -----------------------------------------------------------------------------
# SECRETS GENERATION
# -----------------------------------------------------------------------------

secrets::is_weak_secret() {
    local file="$1"
    [[ ! -f "$file" ]] && return 0

    local size perms content
    size=$(wc -c < "$file" 2>/dev/null | tr -d ' ' || echo "0")
    [[ $size -lt 32 ]] && return 0

    perms=$(get_file_perms "$file")
    [[ "$perms" != "600" ]] && [[ "$perms" != "400" ]] && return 0

    content=$(head -1 "$file" 2>/dev/null | tr -d '\r\n' || echo "")
    [[ -z "$content" ]] && return 0
    case "$content" in
        password|changeme|secret|admin|123456|test|example|TODO|FIXME) return 0 ;;
    esac

    return 1  # not weak
}

secrets::generate() {
    log::header "Generating Secrets"

    if ! validate::directory_exists "$SECRETS_DIR"; then
        log::error "Secrets directory not found: $SECRETS_DIR"
        return 1
    fi

    local required_secrets=("db_password.txt" "pgadmin_password.txt")
    local generated=0 skipped=0

    local env_name
    env_name="$(load::environment 2>/dev/null || echo "unknown")"
    log::info "Generating secrets for environment: $env_name"
    [[ -n "${FORCE:-}" ]] && log::info "⚠️  Force mode: all secrets will be regenerated"
    echo ""

    for secret_file in "${required_secrets[@]}"; do
        local full_path="$SECRETS_DIR/$secret_file"
        log::info "Processing secret: $secret_file"

        local need_generate=false
        if [[ -n "${FORCE:-}" ]]; then
            need_generate=true
        elif ! secrets::is_weak_secret "$full_path"; then
            need_generate=true
        fi

        if [[ "$need_generate" == true ]]; then
            # Backup existing
            if [[ -f "$full_path" ]]; then
                local timestamp backup_file
                timestamp=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo "backup")
                backup_file="$full_path.backup.$timestamp"
                if cp "$full_path" "$backup_file" 2>/dev/null && chmod 600 "$backup_file" 2>/dev/null; then
                    log::info "→ Backup created: $(basename "$backup_file")"
                else
                    log::warn "→ Failed to create backup (continuing anyway)"
                fi
            fi

            # Generate
            local secret=""
            if command -v openssl >/dev/null 2>&1; then
                secret=$(openssl rand -base64 32 2>/dev/null | tr -d '\n=+/' 2>/dev/null)
            fi
            if [[ -z "$secret" ]]; then
                secret=$(head -c 32 /dev/urandom 2>/dev/null | base64 2>/dev/null | tr -d '\n=+/' 2>/dev/null)
            fi
            if [[ -z "$secret" ]]; then
                secret=$(date +%s%N 2>/dev/null | sha256sum 2>/dev/null | head -c 64 | tr -d '\n')
                log::warn "→ Using fallback generator (low entropy)"
            fi

            # Write
            if printf "%s\n" "$secret" > "$full_path" 2>/dev/null; then
                chmod 600 "$full_path" 2>/dev/null || true
                local size
                size=$(wc -c < "$full_path" 2>/dev/null | tr -d ' \t\n' || echo "??")
                log::success "→ Generated: $secret_file ($size bytes)"
                : $((generated++))
            else
                log::error "→ Failed to write: $secret_file"
            fi
        else
            log::info "→ Skipping: $secret_file (already valid)"
            : $((skipped++))
        fi
        echo ""
    done

    log::info "Summary: generated $generated, skipped $skipped out of ${#required_secrets[@]} secrets"
    if [[ $generated -eq 0 && $skipped -gt 0 ]]; then
        log::success "All secrets are up-to-date"
    else
        log::success "Secret generation completed successfully!"
    fi
}

# -----------------------------------------------------------------------------
# MAIN DISPATCHER
# -----------------------------------------------------------------------------

main() {
    local command="${1:-help}"
    shift || true

    while [[ $# -gt 0 ]]; do
        case "$1" in
            FORCE=1|FORCE=true)
                export FORCE=1
                log::info "Force mode enabled (regenerate all secrets)"
                ;;
            *)
                log::warn "Unknown argument: $1"
                ;;
        esac
        shift
    done

    case "$command" in
        check|list|generate)
            secrets::$command
            local exit_code=$?
            [[ $exit_code -ne 0 && "$command" == "generate" ]] && \
                log::error "Secret generation failed with exit code: $exit_code"
            exit $exit_code
            ;;
        verify)
            secrets::check
            ;;
        help|--help|-h)
            echo "Secrets Management Commands"
            echo "Usage: $0 COMMAND [OPTIONS]"
            echo ""
            echo "Commands:"
            echo " check     Validate secrets (permissions, strength)"
            echo " list      List all secrets with metadata"
            echo " generate  Generate missing/weak secrets"
            echo " verify    Alias for 'check'"
            echo ""
            echo "Options:"
            echo " FORCE=1   Regenerate existing secrets (use with generate)"
            echo ""
            echo "Examples:"
            echo " $0 generate"
            echo " $0 generate FORCE=1"
            echo ""
            echo "Security notes:"
            echo " • Secrets are stored in docker/secrets/"
            echo " • File permissions should be 600"
            echo " • Never commit actual secrets to version control"
            echo " • Rotate secrets periodically"
            ;;
        *)
            log::error "Unknown command: $command"
            echo "Use '$0 help' for available commands"
            exit 1
            ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
