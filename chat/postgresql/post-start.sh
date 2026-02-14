#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
source "$CONFIG_DIR/../control/config.sh"

POSTGRES_USER=$POSTGRES_SYNAPSE_USER
POSTGRES_PASSWORD=$POSTGRES_SYNAPSE_PASSWORD
POSTGRES_DB=$POSTGRES_SYNAPSE_DB
PG_CONTAINER="${containers["postgresql-chat"]}"

MAS_DB_USER=mas_user
MAS_DB_PASSWORD=mas_password
MAS_DB_NAME=mas

wait_postgres() {
  until PGPASSWORD="$POSTGRES_PASSWORD" docker exec $PG_CONTAINER pg_isready \
    -U "$POSTGRES_USER" \
    -d "$POSTGRES_DB" \
    -h 127.0.0.1; do
    echo "⏳ Waiting for PostgreSQL to start..."
    sleep 1
  done
}

prepare_postgres() {
  wait_postgres
  echo "🔧 Ensuring database user for Matrix Authentication Service exists..."

  PGPASSWORD="$POSTGRES_PASSWORD" docker exec $PG_CONTAINER psql \
    -U "$POSTGRES_USER" \
    -d postgres \
    -c "DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$MAS_DB_USER') THEN
      CREATE ROLE $MAS_DB_USER LOGIN;
   END IF;
   ALTER ROLE $MAS_DB_USER WITH LOGIN PASSWORD '$MAS_DB_PASSWORD';
END
\$\$;"

  PGPASSWORD="$POSTGRES_PASSWORD" docker exec $PG_CONTAINER psql \
    -U "$POSTGRES_USER" \
    -d postgres \
    -tc "SELECT 1 FROM pg_database WHERE datname = '$MAS_DB_NAME'" | grep -q 1 \
    || PGPASSWORD="$POSTGRES_PASSWORD" docker exec $PG_CONTAINER psql \
      -U "$POSTGRES_USER" \
      -d postgres \
      -c "CREATE DATABASE $MAS_DB_NAME OWNER $MAS_DB_USER;"
}

prepare_postgres
