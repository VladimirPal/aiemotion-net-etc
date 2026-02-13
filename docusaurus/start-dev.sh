#!/bin/bash

SRC="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SRC/.."

"${PROJECT_DIR}/control/scs/bin/cli.sh" --force start docusaurus-dev

#"${PROJECT_DIR}/control/scs/bin/cli.sh" exec docusaurus-builder npm run start -- \
#  --host 0.0.0.0 --port 3004
