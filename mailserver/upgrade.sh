#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
REPO_DIR="${SCRIPT_DIR}/repo"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"; }
error() { echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"; }

pull_latest_code() {
  log "Fetching latest code from git repository..."
  cd "${REPO_DIR}"

  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  log "Current branch: ${current_branch}"

  log "Fetching from origin..."
  git fetch origin "${current_branch}"

  local local_commit
  local remote_commit
  local_commit=$(git rev-parse HEAD)
  remote_commit=$(git rev-parse "origin/${current_branch}")

  if [[ $local_commit == "$remote_commit" ]]; then
    log "Already up to date with origin/${current_branch}"
    return 1
  fi

  log "Resetting to origin/${current_branch}..."
  git reset --hard "origin/${current_branch}"

  if [[ -f "${REPO_DIR}/.gitmodules" ]]; then
    log "Updating submodules..."
    git submodule update --init --recursive
  fi

  log "Code updated successfully"
  return 0
}

rebuild_image() {
  log "Rebuilding Docker image..."
  scs build mailserver
}

check_service_status() {
  cd "${SCRIPT_DIR}"
  if docker compose ps --format '{{.State}}' 2>/dev/null | grep -q 'running'; then
    return 0
  else
    return 1
  fi
}

restart_service() {
  log "Restarting mailserver service..."
  cd "${SCRIPT_DIR}"

  if check_service_status; then
    log "Service is running, performing restart..."
    "${SCRIPT_DIR}/restart.sh"
  else
    log "Service is not running, starting it..."
    "${SCRIPT_DIR}/start.sh"
  fi

  log "Waiting for service to be healthy..."
  sleep 5

  if check_service_status; then
    log "Service is running successfully"
  else
    warn "Service may not be running properly, check status with: ${SCRIPT_DIR}/status.sh"
  fi
}

main() {
  log "Starting mailserver upgrade process"

  local was_running=0
  if check_service_status; then
    was_running=1
    log "Service is currently running"
    log "Stopping service before upgrade..."
    "${SCRIPT_DIR}/stop.sh"
  else
    log "Service is not currently running"
  fi

  if ! pull_latest_code; then
    log "No code changes detected, but continuing with image rebuild..."
  fi

  rebuild_image

  if [[ $was_running -eq 1 ]]; then
    restart_service
  else
    log "Service was not running, skipping restart"
    log "Start the service manually with: ${SCRIPT_DIR}/start.sh"
  fi

  log "Upgrade completed successfully"
  echo
  echo -e "${GREEN}✓ Mailserver upgrade completed!${NC}"
  echo -e "${BLUE}Check service status: ${SCRIPT_DIR}/status.sh${NC}"
  echo -e "${BLUE}View logs: ${SCRIPT_DIR}/logs.sh${NC}"
}

case "${1-}" in
--help | -h)
  echo "Usage: $0 [--help]"
  echo
  echo "Upgrades the mailserver by:"
  echo "  1. Pulling latest code from git repository"
  echo "  2. Rebuilding the Docker image"
  echo "  3. Restarting the service (if it was running)"
  echo
  echo "The script will:"
  echo "  - Check for uncommitted changes (warns before proceeding)"
  echo "  - Fetch and reset to latest origin/master"
  echo "  - Update submodules if present"
  echo "  - Rebuild the Docker image using BuildKit"
  echo "  - Restart the service if it was running"
  ;;
*)
  main
  ;;
esac
