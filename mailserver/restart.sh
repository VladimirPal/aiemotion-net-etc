#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"

"$SCRIPT_DIR/stop.sh"
"$SCRIPT_DIR/start.sh"
