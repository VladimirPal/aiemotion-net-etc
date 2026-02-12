#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

cd "$SCRIPT_DIR"

docker compose up -d --wait --remove-orphans
