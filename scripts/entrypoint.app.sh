#!/bin/sh
set -euo pipefail

# =============================================================================
# ENTRYPOINT FOR APPLICATION CONTAINER
# =============================================================================

if [ -f /run/secrets/db_password ]; then
    DB_PASSWORD=$(cat /run/secrets/db_password | tr -d '\r\n')
    export DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:$DB_PORT/$DB_NAME"
    unset DB_PASSWORD
else
    echo "WARNING: Secret /run/secrets/db_password not found. DATABASE_URL will be incomplete." >&2
fi

exec "$@"
