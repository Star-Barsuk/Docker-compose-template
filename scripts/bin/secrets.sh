#!/bin/bash
# =============================================================================
# SECRETS MANAGEMENT SCRIPT
# =============================================================================

set -euo pipefail

source "$(dirname "$0")/lib.sh"

# -----------------------------------------------------------------------------
# SECRETS VALIDATION
# -----------------------------------------------------------------------------

secrets::check() {
    log::header "Validating Secrets"

    validate::directory_exists "$SECRETS_DIR" || return 1

    local has_errors=0
    local secret_files=()

    # Find all secret files
    while IFS= read -r file; do
        secret_files+=("$file")
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
        perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%p" "$file" | sed 's/^[0-9]*//')
        if [[ "$perms" != "600" ]] && [[ "$perms" != "400" ]]; then
            status="ERROR"
            message="Insecure permissions: $perms (should be 600 or 400)"
            ((has_errors++))
        fi

        # Check file size
        local size
        size=$(wc -c < "$file" | tr -d ' ')
        if [[ $size -lt 32 ]]; then  # At least 32 characters
            if [[ "$status" == "OK" ]]; then
                status="WARN"
            fi
            message="${message:+$message; }Secret may be too short: $size bytes"
        fi

        # Check if file is empty
        if [[ $size -eq 0 ]]; then
            status="ERROR"
            message="Empty secret file"
            ((has_errors++))
        fi

        # Check for common weak secrets
        local content
        content=$(cat "$file" | tr -d '\r\n' | head -c 100)
        if [[ "$content" == "password" ]] || [[ "$content" == "changeme" ]] || \
           [[ "$content" == "secret" ]] || [[ "$content" == "admin" ]]; then
            status="ERROR"
            message="Weak/obvious secret detected"
            ((has_errors++))
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
        log::error "Found $has_errors issue(s) with secrets"
        echo "Recommended actions:"
        echo "  1. Regenerate weak secrets: make secrets-generate"
        echo "  2. Fix permissions: chmod 600 docker/secrets/*.txt"
        return 1
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
        secret_files+=("$file")
    done < <(find "$SECRETS_DIR" -type f -name "*.txt" 2>/dev/null | sort)

    if [[ ${#secret_files[@]} -eq 0 ]]; then
        log::info "No secret files found"
        return 0
    fi

    printf "%-30s %-10s %-20s %s\n" "FILENAME" "SIZE" "PERMISSIONS" "LAST MODIFIED"
    printf "%s\n" "$(printf '%.0s-' {1..80})"

    for file in "${secret_files[@]}"; do
        local filename size perms modified
        filename=$(basename "$file")

        # Get file size
        size=$(wc -c < "$file" | tr -d ' ')
        if [[ $size -ge 1024 ]]; then
            size="$((size / 1024))KB"
        else
            size="${size}B"
        fi

        # Get permissions
        perms=$(stat -c "%a" "$file" 2>/dev/null || stat -f "%p" "$file" | sed 's/^[0-9]*//')

        # Get modification time
        modified=$(stat -c "%y" "$file" 2>/dev/null || date -r "$file" "+%Y-%m-%d %H:%M:%S")
        modified="${modified%% *} ${modified#* }"
        modified="${modified%.*}"

        # Color code permissions
        if [[ "$perms" == "600" ]] || [[ "$perms" == "400" ]]; then
            perms="${COLOR_GREEN}$perms${COLOR_RESET}"
        else
            perms="${COLOR_RED}$perms${COLOR_RESET}"
        fi

        printf "%-30s %-10s %-20s %s\n" "$filename" "$size" "$perms" "$modified"
    done

    echo ""
    log::info "Total secrets: ${#secret_files[@]}"
    log::info "Location: $SECRETS_DIR"

    # Show note about security
    echo ""
    log::warn "IMPORTANT: Never commit secret files to version control!"
    echo "  - Keep .txt files in docker/secrets/"
    echo "  - Add 'docker/secrets/*' to .gitignore"
    echo "  - Use different secrets for different environments"
}

# -----------------------------------------------------------------------------
# SECRETS GENERATION
# -----------------------------------------------------------------------------

secrets::generate() {
    log::header "Generating Secrets"

    validate::directory_exists "$SECRETS_DIR" || {
        log::error "Secrets directory not found: $SECRETS_DIR"
        return 1
    }

    # Define required secrets based on compose files
    local required_secrets=(
        "db_password.txt"
        "pgadmin_password.txt"
    )

    local generated=0
    local skipped=0

    # Process each required secret
    for secret_file in "${required_secrets[@]}"; do
        local full_path="$SECRETS_DIR/$secret_file"

        # Check if secret already exists
        if [[ -f "$full_path" ]]; then
            if [[ -z "${FORCE:-}" ]]; then
                log::info "Skipping existing secret: $secret_file (use FORCE=1 to regenerate)"
                ((skipped++))
                continue
            else
                log::warn "Regenerating existing secret: $secret_file"
            fi
        fi

        log::info "Generating secret: $secret_file"

        # Generate random secret (32 characters, base64 encoded)
        # Using /dev/urandom for cryptographically secure random data
        local secret
        secret=$(openssl rand -base64 32 2>/dev/null || \
                 head -c 32 /dev/urandom | base64 2>/dev/null || \
                 echo "Failed to generate secure secret")

        if [[ "$secret" == "Failed to generate secure secret" ]]; then
            log::error "Failed to generate secure secret for: $secret_file"
            continue
        fi

        # Save secret with secure permissions
        echo "$secret" | tr -d '\n' > "$full_path"

        # Set secure permissions
        chmod 600 "$full_path"

        # Verify the file was created
        if [[ -f "$full_path" ]]; then
            local file_size
            file_size=$(wc -c < "$full_path" | tr -d ' ')
            if [[ $file_size -ge 32 ]]; then
                log::success "Generated: $secret_file (${file_size} bytes)"
                ((generated++))
            else
                log::error "Generated secret is too short: $secret_file"
                rm -f "$full_path"
            fi
        else
            log::error "Failed to create secret file: $secret_file"
        fi
    done

    echo ""

    # Summary
    if [[ $generated -gt 0 ]]; then
        log::success "Successfully generated $generated secret(s)"
    fi

    if [[ $skipped -gt 0 ]]; then
        log::info "Skipped $skipped existing secret(s)"
    fi

    if [[ $generated -eq 0 ]] && [[ $skipped -eq 0 ]]; then
        log::warn "No secrets were generated"
        echo "Required secrets:"
        for secret in "${required_secrets[@]}"; do
            echo "  - $secret"
        done
    fi

    # Show usage instructions
    echo ""
    log::info "Next steps:"
    echo "  1. Verify secrets: make secrets-check"
    echo "  2. List secrets: make secrets-list"
    echo "  3. Update your .env files to reference these secrets"

    return 0
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

        help|--help|-h)
            echo "Secrets Management Commands"
            echo "Usage: $0 COMMAND"
            echo ""
            echo "Commands:"
            echo "  check     Validate secrets (permissions, strength)"
            echo "  list      List all secrets (metadata only)"
            echo "  generate  Generate missing secrets"
            echo ""
            echo "Environment variables:"
            echo "  FORCE=1   Regenerate existing secrets"
            echo ""
            echo "Security notes:"
            echo "  - Secrets are stored in docker/secrets/"
            echo "  - File permissions should be 600"
            echo "  - Never commit secrets to version control"
            ;;

        *)
            log::error "Unknown command: $command"
            echo "Use '$0 help' for available commands"
            exit 1
            ;;
    esac
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
