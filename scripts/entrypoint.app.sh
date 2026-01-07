#!/bin/sh
set -euo pipefail

# =============================================================================
# APPLICATION ENTRYPOINT
# =============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Wait for database to be ready
wait_for_db() {
    local max_attempts=30
    local attempt=1

    log "Waiting for database at ${DB_HOST:-db}:${DB_PORT:-5432}..."

    while [ $attempt -le $max_attempts ]; do
        if nc -z "${DB_HOST:-db}" "${DB_PORT:-5432}" 2>/dev/null; then
            log "Database is ready!"
            return 0
        fi
        log "Attempt $attempt/$max_attempts: Database not ready, retrying in 2 seconds..."
        sleep 2
        attempt=$((attempt + 1))
    done

    log "ERROR: Database not available after $max_attempts attempts"
    return 1
}

# Load database password from secret
load_db_secret() {
    if [ -f /run/secrets/db_password ]; then
        DB_PASSWORD=$(cat /run/secrets/db_password | tr -d '\r\n')
        export DATABASE_URL="postgresql://${DB_USER:-appuser}:$DB_PASSWORD@${DB_HOST:-db}:${DB_PORT:-5432}/${DB_NAME:-appdb}"
        unset DB_PASSWORD
    elif [ -n "${DB_PASSWORD:-}" ]; then
        export DATABASE_URL="postgresql://${DB_USER:-appuser}:$DB_PASSWORD@${DB_HOST:-db}:${DB_PORT:-5432}/${DB_NAME:-appdb}"
    else
        log "WARNING: Database password not found in secrets or environment"
    fi
}

# Main execution
main() {
    # Load database configuration
    load_db_secret

    # Wait for dependencies
    if [ "${WAIT_FOR_DB:-true}" = "true" ]; then
        wait_for_db || exit 1
    fi

    # Run the command
    exec "$@"
}

# Handle signals for graceful shutdown
trap 'log "Received signal, shutting down..."; exit 0' TERM INT

main "$@"
