#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

cd "$SCRIPT_DIR"

docker compose \
  -f "$SCRIPT_DIR/docker-compose.yml" \
  down
