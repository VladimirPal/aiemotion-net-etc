#!/bin/bash

SCRIPT_DIR="$(dirname "$0")"

docker compose \
  -f "$SCRIPT_DIR/docker-compose.yml" \
  exec server authentik --version 2>/dev/null | awk '{print $NF}'
