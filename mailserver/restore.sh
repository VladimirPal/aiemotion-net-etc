#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BACKUP_DIR="${SCRIPT_DIR}/backups"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log(){ echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
warn(){ echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"; }
error(){ echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"; }

show_help(){
  echo "Usage: $0 [backup_file] [options]"
  echo
  echo "Restores Mailserver from a backup archive."
  echo
  echo "Arguments:"
  echo "  backup_file    Path to backup .tar.gz file (optional if only one exists)"
  echo
  echo "Options:"
  echo "  --help, -h     Show this help message"
  echo "  --dry-run      Show what would be restored without actually restoring"
  echo "  --force        Force restore even if mailserver is running"
  echo "  --data-only    Restore only docker-data directory"
  echo "  --config-only  Restore only configuration files"
  echo
  echo "Examples:"
  echo "  $0                                    # Restore from latest backup"
  echo "  $0 20241201_120000.tar.gz            # Restore from specific backup"
  echo "  $0 --dry-run                          # Preview restore operation"
  echo "  $0 --data-only                       # Restore only mail data"
  echo "  $0 --config-only                     # Restore only configuration"
  echo
  echo "Notes:"
  echo "  - Mailserver container will be stopped during restore"
  echo "  - Backup file should be in backups/ directory"
  echo "  - Restore will overwrite existing mail data and configuration"
  echo "  - Use --dry-run to preview operations safely"
}

find_latest_backup(){
  local latest_backup
  latest_backup=$(find "${BACKUP_DIR}" -maxdepth 1 -name "*.tar.gz" -type f | sort -r | head -1)
  
  if [[ -z "$latest_backup" ]]; then
    error "No backup files found in ${BACKUP_DIR}"
    return 1
  fi
  
  echo "$latest_backup"
}

extract_backup(){
  local backup_file="$1"
  local extract_dir="$2"
  
  log "Extracting backup archive: $(basename "$backup_file")"
  
  if ! tar -xzf "$backup_file" -C "$extract_dir"; then
    error "Failed to extract backup archive"
    return 1
  fi
  
  log "Backup extracted to: $extract_dir"
}

check_mailserver_running(){
  if docker ps --format "table {{.Names}}" | grep -q "mailserver"; then
    return 0
  else
    return 1
  fi
}

stop_mailserver(){
  log "Stopping mailserver container..."
  
  if check_mailserver_running; then
    cd "${SCRIPT_DIR}"
    if docker compose stop mailserver; then
      log "Mailserver container stopped successfully"
    else
      error "Failed to stop mailserver container"
      return 1
    fi
  else
    log "Mailserver container is not running"
  fi
}

start_mailserver(){
  log "Starting mailserver container..."
  
  cd "${SCRIPT_DIR}"
  if docker compose up -d mailserver; then
    log "Mailserver container started successfully"
  else
    error "Failed to start mailserver container"
    return 1
  fi
}

backup_existing_data(){
  local backup_timestamp
  backup_timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_path="${SCRIPT_DIR}/docker-data.backup.${backup_timestamp}"
  
  log "Creating backup of existing data: ${backup_path}"
  
  if [[ -d "${SCRIPT_DIR}/docker-data" ]]; then
    if cp -r "${SCRIPT_DIR}/docker-data" "${backup_path}"; then
      log "Existing data backed up to: ${backup_path}"
    else
      warn "Failed to backup existing data - continuing with restore"
    fi
  else
    log "No existing docker-data directory found"
  fi
}

restore_docker_data(){
  local extract_dir="$1"
  local docker_data_backup="${extract_dir}/${BACKUP_NAME}_docker_data"
  
  if [[ ! -d "$docker_data_backup" ]]; then
    error "Docker data backup directory not found: $docker_data_backup"
    return 1
  fi
  
  log "Restoring docker-data directory..."
  
  local docker_data_dir="${SCRIPT_DIR}/docker-data"
  
  if [[ -d "$docker_data_dir" ]]; then
    log "Removing existing docker-data directory..."
    rm -rf "$docker_data_dir"
  fi
  
  if cp -r "$docker_data_backup" "$docker_data_dir"; then
    log "Docker data restored successfully"
    
    local data_size
    data_size=$(du -sh "$docker_data_dir" | cut -f1)
    log "Restored data size: ${data_size}"
  else
    error "Failed to restore docker-data directory"
    return 1
  fi
}

restore_configuration_files(){
  local extract_dir="$1"
  local config_backup="${extract_dir}/${BACKUP_NAME}_config"
  
  if [[ ! -d "$config_backup" ]]; then
    warn "Configuration backup directory not found: $config_backup"
    return 0
  fi
  
  log "Restoring configuration files..."
  
  local compose_source="${config_backup}/compose.yaml"
  local compose_target="${SCRIPT_DIR}/compose.yaml"
  
  if [[ -f "$compose_source" ]]; then
    if cp "$compose_source" "$compose_target"; then
      log "Restored: compose.yaml"
    else
      warn "Failed to restore compose.yaml"
    fi
  else
    warn "Source compose.yaml not found: $compose_source"
  fi
  
  local env_source="${config_backup}/mailserver.env"
  local env_target="${SCRIPT_DIR}/mailserver.env"
  
  if [[ -f "$env_source" ]]; then
    if cp "$env_source" "$env_target"; then
      log "Restored: mailserver.env"
    else
      warn "Failed to restore mailserver.env"
    fi
  else
    warn "Source mailserver.env not found: $env_source"
  fi
  
  log "Configuration files restore completed"
}

show_manifest(){
  local extract_dir="$1"
  local manifest_file="${extract_dir}/${BACKUP_NAME}_manifest.txt"
  
  if [[ -f "$manifest_file" ]]; then
    log "Backup Manifest:"
    echo -e "${BLUE}----------------------------------------${NC}"
    cat "$manifest_file" | sed 's/^/  /'
    echo -e "${BLUE}----------------------------------------${NC}"
  else
    warn "Manifest file not found: $manifest_file"
  fi
}

cleanup_extract_dir(){
  if [[ -n "${extract_dir:-}" && -d "${extract_dir:-}" ]]; then
    rm -rf "${extract_dir:-}"
  fi
}

main(){
  local backup_file=""
  local dry_run=false
  local force=false
  local data_only=false
  local config_only=false
  
  local extract_dir=""
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h)
        show_help
        exit 0
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --force)
        force=true
        shift
        ;;
      --data-only)
        data_only=true
        shift
        ;;
      --config-only)
        config_only=true
        shift
        ;;
      -*)
        error "Unknown option: $1"
        show_help
        exit 1
        ;;
      *)
        if [[ -z "$backup_file" ]]; then
          backup_file="$1"
        else
          error "Multiple backup files specified"
          exit 1
        fi
        shift
        ;;
    esac
  done
  
  if [[ "$data_only" == "true" && "$config_only" == "true" ]]; then
    error "Cannot use --data-only and --config-only together"
    exit 1
  fi
  
  if [[ -z "$backup_file" ]]; then
    backup_file=$(find_latest_backup)
    if [[ $? -ne 0 ]]; then
      exit 1
    fi
    log "Using latest backup: $(basename "$backup_file")"
  fi
  
  if [[ ! -f "$backup_file" ]]; then
    error "Backup file not found: $backup_file"
    exit 1
  fi
  
  BACKUP_NAME=$(basename "$backup_file" .tar.gz)
  
  extract_dir=$(mktemp -d)
  trap 'cleanup_extract_dir' EXIT
  extract_backup "$backup_file" "$extract_dir"
  
  show_manifest "$extract_dir"
  
  if [[ "$dry_run" == "true" ]]; then
    log "DRY RUN: Would restore the following:"
    echo "  - Backup file: $(basename "$backup_file")"
    echo "  - Docker Data: $([[ -d "${extract_dir}/${BACKUP_NAME}_docker_data" ]] && echo "YES" || echo "NO")"
    echo "  - Configuration: $([[ -d "${extract_dir}/${BACKUP_NAME}_config" ]] && echo "YES" || echo "NO")"
    if [[ -d "${extract_dir}/${BACKUP_NAME}_config" ]]; then
      echo "    - compose.yaml: $([[ -f "${extract_dir}/${BACKUP_NAME}_config/compose.yaml" ]] && echo "YES" || echo "NO")"
      echo "    - mailserver.env: $([[ -f "${extract_dir}/${BACKUP_NAME}_config/mailserver.env" ]] && echo "YES" || echo "NO")"
    fi
    echo "  - Extract directory: $extract_dir"
    echo "  - Mailserver container would be stopped and restarted"
    exit 0
  fi
  
  if [[ "$force" != "true" ]]; then
    if check_mailserver_running; then
      error "Mailserver is running. Use --force to override or stop the container first."
      exit 1
    fi
  fi
  
  log "Starting Mailserver restore from: $(basename "$backup_file")"
  
  if [[ "$config_only" == "true" ]]; then
    restore_configuration_files "$extract_dir"
  elif [[ "$data_only" == "true" ]]; then
    stop_mailserver
    backup_existing_data
    restore_docker_data "$extract_dir"
    start_mailserver
  else
    stop_mailserver
    backup_existing_data
    restore_docker_data "$extract_dir"
    restore_configuration_files "$extract_dir"
    start_mailserver
  fi
  
  log "Restore completed successfully"
  echo
  echo -e "${GREEN}✓ Restore completed successfully!${NC}"
  echo -e "${BLUE}Mailserver should be running and accessible${NC}"
  echo -e "${YELLOW}⚠️  Please verify mail functionality and check logs${NC}"
}

main "$@"
