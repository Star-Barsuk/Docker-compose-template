#!/bin/sh
set -e

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting application..."

if [ -f /run/secrets/db_password ]; then
    DB_PASSWORD=$(cat /run/secrets/db_password | tr -d '\r\n')
    export DATABASE_URL="postgresql://${DB_USER:-appuser}:$DB_PASSWORD@${DB_HOST:-db}:${DB_PORT:-5432}/${DB_NAME:-appdb}"
    unset DB_PASSWORD
fi

exec "$@"
