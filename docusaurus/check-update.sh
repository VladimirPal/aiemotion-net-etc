#!/bin/bash

SRC="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SRC/.."

"${PROJECT_DIR}/control/scs/bin/cli.sh" exec docusaurus-builder npm run ncu
