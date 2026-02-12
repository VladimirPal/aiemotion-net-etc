#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BACKUP_DIR="${SCRIPT_DIR}/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="${TIMESTAMP}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log(){ echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
warn(){ echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"; }
error(){ echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"; }

create_backup_dir(){ 
  mkdir -p "${BACKUP_DIR}"; 
  log "Backup directory: ${BACKUP_DIR}"; 
}

perform_docker_data_backup(){
  log "Starting Docker data backup..."
  
  local docker_data_dir="${SCRIPT_DIR}/docker-data"
  local backup_data_dir="${BACKUP_DIR}/${BACKUP_NAME}_docker_data"
  
  if [[ ! -d "${docker_data_dir}" ]]; then
    error "Docker data directory not found: ${docker_data_dir}"
    return 1
  fi
  
  mkdir -p "${backup_data_dir}"
  
  log "Backing up mail data, state, logs, and configuration..."
  
  if cp -r "${docker_data_dir}"/* "${backup_data_dir}/"; then
    log "Docker data backup completed: ${backup_data_dir}"
    
    local data_size
    data_size=$(du -sh "${backup_data_dir}" | cut -f1)
    log "Backup size: ${data_size}"
  else
    error "Docker data backup failed"
    return 1
  fi
}

backup_configuration_files(){
  log "Backing up configuration files..."
  
  local config_backup_dir="${BACKUP_DIR}/${BACKUP_NAME}_config"
  mkdir -p "${config_backup_dir}"
  
  local compose_file="${SCRIPT_DIR}/compose.yaml"
  if [[ -f "$compose_file" ]]; then
    cp "$compose_file" "${config_backup_dir}/compose.yaml"
    log "Backed up: compose.yaml"
  else
    warn "Compose file not found: $compose_file"
  fi
  
  local env_file="${SCRIPT_DIR}/mailserver.env"
  if [[ -f "$env_file" ]]; then
    cp "$env_file" "${config_backup_dir}/mailserver.env"
    log "Backed up: mailserver.env"
  else
    warn "Environment file not found: $env_file"
  fi
  
  log "Configuration files backup completed: ${config_backup_dir}"
}

create_backup_manifest(){
  local manifest_file="${BACKUP_DIR}/${BACKUP_NAME}_manifest.txt"
  
  local docker_image_version
  docker_image_version=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "it-pal/mailserver" | head -1 || echo "Unknown")
  
  local container_status
  container_status=$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep "mailserver" || echo "Not running")
  
  local data_directories
  data_directories=$(find "${SCRIPT_DIR}/docker-data" -type d -name "*" 2>/dev/null | sort || echo "Unable to enumerate directories")

  {
    echo "Mailserver Backup Manifest"
    echo "=========================="
    echo "Backup Date: $(date)"
    echo "DatePrefix: ${TIMESTAMP}"
    echo "Backup Name: ${BACKUP_NAME}"
    echo "Backup Type: Docker Data + Configuration Files"
    echo
    echo "Docker Data Backup: ${BACKUP_DIR}/${BACKUP_NAME}_docker_data"
    echo "Configuration Backup: ${BACKUP_DIR}/${BACKUP_NAME}_config"
    echo
    echo "Backed Up Directories:"
    echo "${data_directories}" | sed 's/^/- /'
    echo
    echo "System Information:"
    echo "- Docker Image: ${docker_image_version}"
    echo "- Container Status: ${container_status}"
    echo "- Backup Script: ${SCRIPT_DIR}/backup.sh"
    echo "- Hostname: $(hostname)"
    echo
    echo "Backup Contents:"
    echo "- mail-data/: All user mailboxes and email data"
    echo "- mail-state/: Mail server state files (Postfix, Dovecot, etc.)"
    echo "- mail-logs/: Mail server logs and log rotation data"
    echo "- config/: Configuration files (accounts, DKIM keys, etc.)"
    echo "- compose.yaml: Docker Compose configuration"
    echo "- mailserver.env: Environment variables and settings"
    echo
    echo "Notes:"
    echo "- This backup contains all persistent mail data and configuration"
    echo "- Mail server will be stopped during restore process"
    echo "- DKIM keys and SSL certificates are included in the backup"
    echo "- IMPORTANT: Ensure mail server is stopped before restore"
    echo "- Restore will replace all existing mail data"
  } > "${manifest_file}"

  log "Backup manifest created: ${manifest_file}"
  
  log "Backup Manifest Contents:"
  echo -e "${BLUE}----------------------------------------${NC}"
  cat "${manifest_file}" | sed 's/^/  /'
  echo -e "${BLUE}----------------------------------------${NC}"
}

create_final_archive(){
  log "Creating final backup archive..."
  cd "${BACKUP_DIR}"
  
  local archive_name="${BACKUP_NAME}.tar.gz"
  
  if tar -czf "${archive_name}" \
    "${BACKUP_NAME}_docker_data" \
    "${BACKUP_NAME}_config" \
    "${BACKUP_NAME}_manifest.txt" 2>/dev/null; then
    
    log "Final backup archive created: ${archive_name}"
    
    rm -rf "${BACKUP_NAME}_docker_data" "${BACKUP_NAME}_config" "${BACKUP_NAME}_manifest.txt"
    log "Individual backup files cleaned up"
  else
    warn "Failed to create final archive, keeping individual files"
  fi
}

main(){
  create_backup_dir
  log "Starting Mailserver backup"
  log "Backup name: ${BACKUP_NAME}"

  if ! perform_docker_data_backup; then
    error "Docker data backup failed"
    exit 1
  fi

  backup_configuration_files

  create_backup_manifest
  create_final_archive

  log "Backup completed successfully"
  log "Archive location: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"
  echo
  echo -e "${GREEN}✓ Backup completed successfully!${NC}"
  echo -e "${BLUE}Archive: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz${NC}"
  echo -e "${BLUE}SCS will handle S3 upload and cleanup${NC}"
}

case "${1:-}" in
  --help|-h)
    echo "Usage: $0 [--help]"
    echo
    echo "Creates:"
    echo "  - Complete backup of docker-data directory (mail data, state, logs, config)"
    echo "  - Configuration files backup (compose.yaml, mailserver.env)"
    echo "Outputs: Single .tar.gz archive in backups/ directory"
    echo "SCS handles: S3 upload, retention, service restart"
    ;;
  *)
    main
    ;;
esac
