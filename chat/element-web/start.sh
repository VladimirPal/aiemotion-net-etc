#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_PATH="/etc/chat/element-web/repo"
DOCKERFILE_PATH="/etc/chat/element-web/Dockerfile"
IMAGE_NAME="element-web-builder"
CONTAINER_NAME="element-web-builder"

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo $0"
  exit 1
fi

cd "$SCRIPT_DIR"

if ! docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
  echo "→ Creating builder container…"
  docker create \
    --name "$CONTAINER_NAME" \
    -v "$REPO_PATH":/app \
    -w /app \
    "$IMAGE_NAME" \
    sleep infinity
fi

if ! docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -qx "$CONTAINER_NAME"; then
  echo "→ Starting builder container…"
  docker start "$CONTAINER_NAME"
fi

echo "→ Installing dependencies inside container…"
docker exec "$CONTAINER_NAME" yarn install
echo "✓ Dependencies installed"

echo "→ Building the app inside container…"
docker exec "$CONTAINER_NAME" yarn build
echo "✓ Build finished"

echo "→ Stopping builder container…"
docker stop "$CONTAINER_NAME"
echo "✓ Builder container stopped"

/etc/chat/element-web/upload.sh
