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

    # Method 1: Use ls -l and parse the symbolic permissions
    local ls_output
    ls_output=$(ls -l "$file" 2>/dev/null)

    if [[ -n "$ls_output" ]]; then
        # Extract the permission string (e.g., "-rw-r--r--")
        local perm_str
        perm_str=$(echo "$ls_output" | awk '{print $1}')

        # Debug output (commented out)
        # echo "DEBUG: perm_str='$perm_str'" >&2

        # Convert symbolic permissions to octal
        local owner=0 group=0 other=0

        # Owner permissions
        [[ ${perm_str:1:1} == "r" ]] && owner=$((owner + 4))
        [[ ${perm_str:2:1} == "w" ]] && owner=$((owner + 2))
        [[ ${perm_str:3:1} == "x" ]] && owner=$((owner + 1))
        [[ ${perm_str:3:1} == "s" ]] && owner=$((owner + 1)) # setuid
        [[ ${perm_str:3:1} == "S" ]] && owner=$((owner + 1)) # setuid

        # Group permissions
        [[ ${perm_str:4:1} == "r" ]] && group=$((group + 4))
        [[ ${perm_str:5:1} == "w" ]] && group=$((group + 2))
        [[ ${perm_str:6:1} == "x" ]] && group=$((group + 1))
        [[ ${perm_str:6:1} == "s" ]] && group=$((group + 1)) # setgid
        [[ ${perm_str:6:1} == "S" ]] && group=$((group + 1)) # setgid

        # Other permissions
        [[ ${perm_str:7:1} == "r" ]] && other=$((other + 4))
        [[ ${perm_str:8:1} == "w" ]] && other=$((other + 2))
        [[ ${perm_str:9:1} == "x" ]] && other=$((other + 1))
        [[ ${perm_str:9:1} == "t" ]] && other=$((other + 1)) # sticky bit
        [[ ${perm_str:9:1} == "T" ]] && other=$((other + 1)) # sticky bit

        printf "%d%d%d\n" "$owner" "$group" "$other"
        return 0
    fi

    # Method 2: Try stat command (but parse output carefully)
    if command -v stat >/dev/null 2>&1; then
        # Try different stat formats
        local stat_output
        stat_output=$(stat --format="%a" "$file" 2>/dev/null)
        if [[ -n "$stat_output" ]] && [[ "$stat_output" =~ ^[0-9]{3,4}$ ]]; then
            echo "$stat_output"
            return 0
        fi

        # Try BSD style
        stat_output=$(stat -f "%p" "$file" 2>/dev/null)
        if [[ -n "$stat_output" ]]; then
            # Extract last 3-4 digits for octal permissions
            echo "$stat_output" | grep -o '[0-9][0-9][0-9][0-9]$' | sed 's/^0*//'
            return 0
        fi
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

    # Try date command first
    if date -r "$file" "+%Y-%m-%d %H:%M:%S" 2>/dev/null; then
        return 0
    fi

    # Fallback to ls -l
    ls -l --time-style="+%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null | awk 'NR==1 {print $6, $7}' || echo "unknown"
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
        if [[ $size -lt 32 ]]; then  # At least 32 characters
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

        # Check for common weak secrets (only check first line)
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

    # Overall status
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

    # Find all secret files
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

        # Get file size
        size=$(wc -c < "$file" 2>/dev/null | tr -d ' ' || echo "0")
        if [[ $size -ge 1024 ]]; then
            size="$((size / 1024))KB"
        else
            size="${size}B"
        fi

        # Get permissions
        perms=$(get_file_perms "$file")

        # Get modification time
        modified=$(get_file_mtime "$file")

        # Color code permissions
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

    # Check if secrets are referenced in environment
    local env_name
    if env_name="$(load::environment 2>/dev/null)"; then
        echo ""
        log::info "Active environment: $env_name"

        # Check for secret references in environment files
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

    # Show note about security
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

# -----------------------------------------------------------------------------
# SECRETS GENERATION
# -----------------------------------------------------------------------------

secrets::generate() {
    log::header "Generating Secrets"

    validate::directory_exists "$SECRETS_DIR" || {
        log::error "Secrets directory not found: $SECRETS_DIR"
        return 1
    }

    # Define required secrets
    local required_secrets=(
        "db_password.txt"
        "pgadmin_password.txt"
    )

    local generated=0
    local skipped=0
    local errors=0

    # Load environment
    local env_name
    env_name="$(load::environment 2>/dev/null || echo "default")"

    log::info "Generating secrets for environment: $env_name"
    echo ""

    # Process each required secret
    for secret_file in "${required_secrets[@]}"; do
        local full_path="$SECRETS_DIR/$secret_file"

        # Check if secret already exists
        if [[ -f "$full_path" ]] && [[ -s "$full_path" ]]; then
            if [[ -z "${FORCE:-}" ]]; then
                log::info "Skipping existing secret: $secret_file"
                ((skipped++))
                continue
            else
                log::warn "Regenerating existing secret: $secret_file"
                # Backup old secret
                local timestamp
                timestamp=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo "backup")
                local backup_file="${full_path}.backup.${timestamp}"
                if cp "$full_path" "$backup_file" 2>/dev/null; then
                    chmod 600 "$backup_file" 2>/dev/null
                    log::debug "Backup created: $(basename "$backup_file")"
                else
                    log::warn "Failed to create backup for: $secret_file"
                fi
            fi
        fi

        log::info "Generating secret: $secret_file"

        # Generate secret using multiple fallback methods
        local secret=""

        # Method 1: Try openssl first (most reliable)
        if command -v openssl >/dev/null 2>&1; then
            secret=$(openssl rand -hex 24 2>/dev/null)
            if [[ -n "$secret" ]]; then
                log::debug "Generated using openssl"
            fi
        fi

        # Method 2: Try /dev/urandom with proper xxd usage
        if [[ -z "$secret" ]] && [[ -r "/dev/urandom" ]] && command -v xxd >/dev/null 2>&1; then
            # Исправлено: правильное использование xxd
            secret=$(head -c 24 /dev/urandom 2>/dev/null | xxd -ps -c 24 2>/dev/null | tr -d '\n')
            if [[ -n "$secret" ]]; then
                log::debug "Generated using /dev/urandom"
            fi
        fi

        # Method 3: Try /dev/urandom with od
        if [[ -z "$secret" ]] && [[ -r "/dev/urandom" ]] && command -v od >/dev/null 2>&1; then
            secret=$(head -c 24 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')
            if [[ -n "$secret" ]]; then
                log::debug "Generated using od"
            fi
        fi

        # Method 4: Final fallback - use date and random
        if [[ -z "$secret" ]]; then
            # Base64 encoding as fallback
            secret=$(echo "$(date +%s%N)$$$RANDOM" | base64 2>/dev/null | tr -d '\n=+/' | head -c 48)
            if [[ -z "$secret" ]]; then
                # Ultimate fallback
                secret="emergency_secret_$(date +%s)_${RANDOM}"
            fi
            log::warn "Using fallback method for: $secret_file"
        fi

        # Validate secret is not empty
        if [[ -z "$secret" ]]; then
            log::error "Failed to generate secret for: $secret_file"
            ((errors++))
            continue
        fi

        # Save the secret
        if printf "%s" "$secret" > "$full_path" 2>/dev/null; then
            # Set secure permissions
            chmod 600 "$full_path" 2>/dev/null || chmod 400 "$full_path" 2>/dev/null

            # Verify the file was created and has content
            if [[ -f "$full_path" ]] && [[ -s "$full_path" ]]; then
                local file_size
                file_size=$(wc -c < "$full_path" 2>/dev/null | tr -d ' ' || echo "0")
                if [[ $file_size -gt 0 ]]; then
                    log::success "Generated: $secret_file (${file_size} bytes)"
                    ((generated++))
                else
                    log::error "Generated empty secret: $secret_file"
                    rm -f "$full_path" 2>/dev/null
                    ((errors++))
                fi
            else
                log::error "Failed to create secret file: $secret_file"
                ((errors++))
            fi
        else
            log::error "Failed to write secret file: $secret_file"
            ((errors++))
        fi
    done

    echo ""
    log::info "Summary:"
    log::info "  Generated: $generated"
    log::info "  Skipped: $skipped"
    log::info "  Errors: $errors"

    # Return appropriate exit code
    if [[ $errors -gt 0 ]]; then
        log::error "Failed to generate $errors secret(s)"
        return 1
    elif [[ $generated -eq 0 ]] && [[ $skipped -gt 0 ]]; then
        log::info "All secrets already exist. Use FORCE=1 to regenerate."
        return 0
    else
        log::success "Secrets generated successfully"
        echo ""
        echo "Next steps:"
        echo "  1. Run 'make secrets-check' to validate"
        echo "  2. Run 'make secrets-list' to view"
        echo "  3. Restart services if needed"
        return 0
    fi
}

# -----------------------------------------------------------------------------
# MAIN DISPATCHER
# -----------------------------------------------------------------------------

main() {
    local command="${1:-help}"

    case "$command" in
        check|list|generate)
            secrets::$command
            ;;

        verify)
            # Alias for check
            secrets::check
            ;;

        help|--help|-h)
            echo "Secrets Management Commands"
            echo "Usage: $0 COMMAND"
            echo ""
            echo "Commands:"
            echo "  check      Validate secrets (permissions, strength)"
            echo "  list       List all secrets with metadata"
            echo "  generate   Generate missing/weak secrets"
            echo "  verify     Alias for 'check'"
            echo ""
            echo "Environment variables:"
            echo "  FORCE=1    Regenerate existing secrets"
            echo ""
            echo "Examples:"
            echo "  $0 check            # Validate all secrets"
            echo "  $0 list             # List all secrets"
            echo "  FORCE=1 $0 generate # Regenerate all secrets"
            echo ""
            echo "Security notes:"
            echo "  • Secrets are stored in docker/secrets/"
            echo "  • File permissions should be 600"
            echo "  • Never commit actual secrets to version control"
            echo "  • Rotate secrets periodically"
            ;;

        *)
            log::error "Unknown command: $command"
            echo "Use '$0 help' for available commands"
            exit 1
            ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
