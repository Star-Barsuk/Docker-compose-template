#!/bin/bash
# =============================================================================
# SECRETS MANAGEMENT
# =============================================================================

set -euo pipefail

# Initialize paths and source lib.sh
source "$(dirname "$0")/init.sh"

# -----------------------------------------------------------------------------
# CONSTANTS
# -----------------------------------------------------------------------------
readonly REQUIRED_SECRETS=(
    "db_password.txt"
    "pgadmin_password.txt"
)

# -----------------------------------------------------------------------------
# UTILITY FUNCTIONS
# -----------------------------------------------------------------------------
secrets::is_secure() {
    local file="$1"

    [[ -f "$file" ]] || return 1

    local perms
    perms=$(stat -c "%a" "$file" 2>/dev/null || echo "000")
    [[ "$perms" == "600" ]] || [[ "$perms" == "400" ]] || return 1

    local size
    size=$(wc -c < "$file" 2>/dev/null || echo 0)
    [[ $size -ge 32 ]] || return 1

    return 0
}

secrets::generate_one() {
    local file="$1"

    mkdir -p "$(dirname "$file")"

    local secret=""

    if command -v openssl >/dev/null 2>&1; then
        secret=$(openssl rand -base64 48 2>/dev/null | tr -d '\n=+/' || echo "")
    fi

    if [[ ${#secret} -lt 32 ]]; then
        secret="${secret}$(date +%s%N | sha256sum | cut -d' ' -f1)"
        secret="${secret:0:64}"
    fi

    echo "$secret" > "$file"
    chmod 600 "$file" 2>/dev/null || true

    if [[ -f "$file" ]] && [[ $(wc -c < "$file") -ge 32 ]]; then
        echo "$secret"
        return 0
    else
        log::error "Failed to write secret to $file"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# COMMANDS
# -----------------------------------------------------------------------------
secrets::check() {
    log::header "Checking Secrets"

    validate::dir_exists "$SECRETS_DIR" || return 1

    local issues=0

    for secret in "${REQUIRED_SECRETS[@]}"; do
        local file="$SECRETS_DIR/$secret"

        if [[ ! -f "$file" ]]; then
            log::error "Missing: $secret"
            : $((issues++))
        elif secrets::is_secure "$file"; then
            log::success "OK: $secret"
        else
            log::warn "Insecure: $secret"
            : $((issues++))
        fi
    done

    if [[ $issues -eq 0 ]]; then
        log::success "All secrets are secure"
        return 0
    else
        log::warn "Found $issues issue(s) with secrets"
        echo "Run 'make secrets-generate' to fix"
        return 1
    fi
}

secrets::list() {
    log::header "Secrets List"

    validate::dir_exists "$SECRETS_DIR" || return 1

    local files=()
    while IFS= read -r file; do
        [[ -f "$file" ]] && files+=("$file")
    done < <(find "$SECRETS_DIR" -name "*.txt" -type f 2>/dev/null | sort)

    if [[ ${#files[@]} -eq 0 ]]; then
        log::info "No secrets found"
        echo ""
        echo "Generate secrets with: make secrets-generate"
        return 0
    fi

    printf "%-30s %-10s %-10s %s\n" "FILE" "SIZE" "PERMS" "STATUS"
    printf "%s\n" "$(printf '=%.0s' {1..70})"

    for file in "${files[@]}"; do
        local name size perms status color
        name="$(basename "$file")"
        size_bytes=$(wc -c < "$file" 2>/dev/null || echo 0)
        size=$(awk -v bytes="$size_bytes" 'BEGIN {printf "%.1fK", bytes/1024}')
        perms=$(stat -c "%a" "$file" 2>/dev/null || echo "?")

        if secrets::is_secure "$file"; then
            status="SECURE"
            color="$COLOR_GREEN"
        else
            status="INSECURE"
            color="$COLOR_RED"
        fi

        printf "%-30s %-10s %-10s ${color}%s${COLOR_RESET}\n" \
            "$name" "$size" "$perms" "$status"
    done

    echo ""
    log::info "Total secrets: ${#files[@]}"
    log::info "Location: $(relpath "$SECRETS_DIR")"
}

secrets::generate() {
    log::header "Generating Secrets"

    validate::dir_exists "$SECRETS_DIR" || return 1

    local generated=0
    local skipped=0
    local failed=0

    log::info "Generating secrets..."
    echo ""

    for secret in "${REQUIRED_SECRETS[@]}"; do
        local file="$SECRETS_DIR/$secret"

        if [[ "${FORCE:-}" == "1" ]] || ! secrets::is_secure "$file"; then
            if [[ -f "$file" ]]; then
                local timestamp
                timestamp=$(date +%Y%m%d_%H%M%S 2>/dev/null || echo "backup")
                local backup="$file.backup.$timestamp"
                if cp "$file" "$backup" 2>/dev/null; then
                    chmod 600 "$backup" 2>/dev/null || true
                fi
            fi

            if secrets::generate_one "$file" >/dev/null; then
                log::success "Generated: $secret"
                : $((generated++))
            else
                log::error "Failed to generate: $secret"
                : $((failed++))
            fi
        else
            log::info "Skipping: $secret (already secure)"
            : $((skipped++))
        fi
    done

    echo ""
    if [[ $generated -gt 0 ]]; then
        log::success "Successfully generated $generated secret(s)"
    fi
    if [[ $skipped -gt 0 ]]; then
        log::info "Skipped $skipped secret(s) (already secure)"
    fi
    if [[ $failed -gt 0 ]]; then
        log::error "Failed to generate $failed secret(s)"
        return 1
    fi

    if [[ $generated -eq 0 ]] && [[ $skipped -eq 0 ]] && [[ $failed -eq 0 ]]; then
        log::info "No secrets to process"
    fi

    return $((failed > 0))
}

# -----------------------------------------------------------------------------
# MAIN DISPATCHER
# -----------------------------------------------------------------------------
main() {
    local cmd="${1:-help}"

    case "$cmd" in
        check|list|generate)
            secrets::$cmd
            ;;
        help|--help|-h)
            cat << EOF
Secrets Management

Usage: $0 COMMAND

Commands:
  check     Validate secret security
  list      List all secrets with status
  generate  Generate missing/weak secrets

Options:
  FORCE=1   Regenerate all secrets (use with generate command)

Examples:
  $0 check
  $0 list
  $0 generate
  FORCE=1 $0 generate
EOF
            ;;
        *)
            log::error "Unknown command: $cmd"
            echo "Use '$0 help' for usage"
            exit 1
            ;;
    esac
}

# Only run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
