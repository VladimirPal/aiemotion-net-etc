#!/bin/bash

set -e

COMPOSE_FILE="/etc/authentik/docker-compose.yml"
AUTHENTIK_COMPOSE_URL="https://goauthentik.io/docker-compose.yml"
BACKUP_COMPOSE="/etc/authentik/docker-compose.yml.bak"

echo "🔄 Downloading the latest docker-compose.yml from Authentik..."
curl -fsSL "$AUTHENTIK_COMPOSE_URL" -o "$COMPOSE_FILE.new"

if [ ! -s "$COMPOSE_FILE.new" ]; then
  echo "❌ Failed to download docker-compose.yml. Update aborted."
  rm -f "$COMPOSE_FILE.new"
  exit 1
fi

mv "$COMPOSE_FILE.new" "$COMPOSE_FILE"
echo "✅ Updated docker-compose.yml applied."

echo "🛑 Stopping and removing old Authentik containers..."
/etc/control/scs/bin/cli.sh stop authentik

echo "⬇️ Pulling the latest Authentik images..."
docker compose -f "$COMPOSE_FILE" pull

echo "🚀 Starting Authentik with updated images..."
/etc/control/scs/bin/cli.sh start authentik

echo "✅ Authentik update completed successfully!"
