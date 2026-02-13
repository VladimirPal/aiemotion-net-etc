#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
BACKUP_DIR="${SCRIPT_DIR}/backups"
RESTORE_DIR="${SCRIPT_DIR}/restore_temp"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log(){ echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*"; }
warn(){ echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $*"; }
error(){ echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*"; }

show_usage(){
  echo "Usage: $0 <backup_archive> [options]"
  echo
  echo "Arguments:"
  echo "  backup_archive    Path to the backup .tar.gz file to restore"
  echo
  echo "Options:"
  echo "  --dry-run         Show what would be restored without actually doing it"
  echo "  --force           Skip confirmation prompts (DANGEROUS)"
  echo "  --help, -h        Show this help message"
  echo
  echo "Examples:"
  echo "  $0 backups/20241201_143022.tar.gz"
  echo "  $0 backups/20241201_143022.tar.gz --dry-run"
  echo "  $0 backups/20241201_143022.tar.gz --force"
  echo
  echo "IMPORTANT:"
  echo "  - This will STOP all Authentik services during restore"
  echo "  - Existing data will be OVERWRITTEN"
  echo "  - Make sure you have a current backup before proceeding"
  echo "  - The script will ask for confirmation unless --force is used"
}

project_name_from_env(){
  local f="${1}"
  if [[ -f "$f" ]]; then
    grep -E '^[[:space:]]*COMPOSE_PROJECT_NAME=' "$f" | tail -n1 | cut -d= -f2- | tr -d '"' | tr -d '\r' | xargs || true
  fi
}

compose_cmd(){ echo "docker compose --env-file ${SCRIPT_DIR}/.env -f ${SCRIPT_DIR}/docker-compose.yml"; }

validate_backup_archive(){
  local archive_path="$1"
  
  if [[ ! -f "$archive_path" ]]; then
    error "Backup archive not found: $archive_path"
    return 1
  fi
  
  if [[ ! "$archive_path" =~ \.tar\.gz$ ]]; then
    error "Backup archive must be a .tar.gz file"
    return 1
  fi
  
  log "Validating backup archive: $archive_path"
  
  if ! tar -tzf "$archive_path" >/dev/null 2>&1; then
    error "Invalid or corrupted backup archive"
    return 1
  fi
  
  log "✓ Backup archive is valid"
}

extract_backup_archive(){
  local archive_path="$1"
  
  mkdir -p "${RESTORE_DIR}"
  
  if tar -xzf "$archive_path" -C "${RESTORE_DIR}"; then
    local backup_name
    backup_name=$(ls "${RESTORE_DIR}" | grep -E '^[0-9]{8}_[0-9]{6}$' | head -1)
    
    if [[ -z "$backup_name" ]]; then
      error "Could not determine backup name from extracted files"
      return 1
    fi
    
    echo "$backup_name"
  else
    error "Failed to extract backup archive"
    return 1
  fi
}

show_backup_info(){
  local backup_name="$1"
  local manifest_file="${RESTORE_DIR}/${backup_name}/manifest.txt"
  
  if [[ -f "$manifest_file" ]]; then
    log "Backup Information:"
    echo -e "${BLUE}----------------------------------------${NC}"
    cat "$manifest_file" | sed 's/^/  /'
    echo -e "${BLUE}----------------------------------------${NC}"
  else
    warn "No manifest file found, proceeding with basic restore"
  fi
}

confirm_restore(){
  local backup_name="$1"
  
  echo
  echo -e "${RED}⚠️  WARNING: This will restore Authentik from backup!${NC}"
  echo -e "${RED}⚠️  All current data will be OVERWRITTEN!${NC}"
  echo
  echo "Backup to restore: $backup_name"
  echo "Services will be stopped during restore"
  echo
  read -p "Are you sure you want to continue? (type 'yes' to confirm): " confirmation
  
  if [[ "$confirmation" != "yes" ]]; then
    log "Restore cancelled by user"
    exit 0
  fi
}

stop_services(){
  log "Stopping Authentik services..."
  cd "${SCRIPT_DIR}"
  
  local dc=$(compose_cmd)
  if ${dc} stop; then
    log "✓ Services stopped successfully"
  else
    warn "Some services may not have stopped cleanly"
  fi
}

restore_postgres(){
  local backup_name="$1"
  local db_backup_file="${RESTORE_DIR}/${backup_name}/postgres.sql"
  
  if [[ ! -f "$db_backup_file" ]]; then
    warn "PostgreSQL backup file not found: $db_backup_file"
    return 0
  fi
  
  log "Starting PostgreSQL database restore..."
  cd "${SCRIPT_DIR}"
  
  local dc=$(compose_cmd)
  ${dc} up -d postgresql
  
  log "Waiting for PostgreSQL to be ready..."
  local max_attempts=30
  local attempt=0
  
  while [[ $attempt -lt $max_attempts ]]; do
    if docker compose exec postgresql pg_isready -U authentik -d authentik >/dev/null 2>&1; then
      break
    fi
    sleep 2
    ((attempt++))
  done
  
  if [[ $attempt -eq $max_attempts ]]; then
    error "PostgreSQL failed to start within expected time"
    return 1
  fi
  
  log "PostgreSQL is ready, restoring database..."
  
  docker compose exec postgresql psql -U authentik -d postgres -c "DROP DATABASE IF EXISTS authentik;"
  docker compose exec postgresql psql -U authentik -d postgres -c "CREATE DATABASE authentik;"
  
  if docker compose exec -T postgresql psql -U authentik -d authentik < "$db_backup_file"; then
    log "✓ PostgreSQL database restored successfully"
  else
    error "PostgreSQL database restore failed"
    return 1
  fi
}

restore_volumes(){
  local backup_name="$1"
  local volumes_backup_dir="${RESTORE_DIR}/${backup_name}/volumes"
  
  if [[ ! -d "$volumes_backup_dir" ]]; then
    warn "Volumes backup directory not found: $volumes_backup_dir"
    return 0
  fi
  
  log "Starting Docker volumes restore..."
  cd "${SCRIPT_DIR}"
  
  local project_name
  project_name=$(project_name_from_env "${SCRIPT_DIR}/.env")
  if [[ -z "${project_name}" ]]; then project_name="authentik"; fi
  
  local failed=0
  
  for volume_file in "${volumes_backup_dir}"/*.tar.gz; do
    if [[ ! -f "$volume_file" ]]; then continue; fi
    
    local volume_name
    volume_name=$(basename "$volume_file" .tar.gz)
    
    log "Restoring volume: $volume_name"
    
    if docker volume inspect "$volume_name" >/dev/null 2>&1; then
      docker volume rm "$volume_name" || true
    fi
    
    if docker volume create "$volume_name" >/dev/null 2>&1; then
      if docker run --rm -v "$volume_name:/data" -v "$volumes_backup_dir:/backup" alpine \
         tar xzf "/backup/$(basename "$volume_file")" -C /data; then
        log "✓ Volume $volume_name restored"
      else
        warn "Failed to restore volume: $volume_name"
        failed=1
      fi
    else
      warn "Failed to create volume: $volume_name"
      failed=1
    fi
  done
  
  if [[ $failed -eq 0 ]]; then
    log "✓ All volumes restored successfully"
  else
    warn "Some volume restores failed"
  fi
  
  return $failed
}

restore_media_files(){
  local backup_name="$1"
  local media_backup_dir="${RESTORE_DIR}/${backup_name}/media"
  
  if [[ ! -d "$media_backup_dir" ]]; then
    warn "Media backup directory not found: $media_backup_dir"
    return 0
  fi
  
  log "Starting media files restore..."
  cd "${SCRIPT_DIR}"
  
  local failed=0
  
  if [[ -f "${RESTORE_DIR}/${backup_name}/.env" ]]; then
    if [[ -f "./.env" ]]; then
      cp "./.env" "./.env.backup.$(date +%Y%m%d_%H%M%S)" || true
      log "Current .env file backed up as .env.backup.*"
    fi
    if cp "${RESTORE_DIR}/${backup_name}/.env" "./"; then
      log "✓ Environment configuration (.env) restored"
    else
      warn "Failed to restore .env file"
      failed=1
    fi
  else
    warn ".env file not found in backup, skipping"
  fi
  
  if [[ -d "${media_backup_dir}/media" ]]; then
    if [[ -d "./media" ]]; then
      rm -rf "./media"
    fi
    if cp -r "${media_backup_dir}/media" "./"; then
      log "✓ Media files restored"
    else
      warn "Failed to restore media files"
      failed=1
    fi
  fi
  
  if [[ -d "${media_backup_dir}/custom-templates" ]]; then
    if [[ -d "./custom-templates" ]]; then
      rm -rf "./custom-templates"
    fi
    if cp -r "${media_backup_dir}/custom-templates" "./"; then
      log "✓ Custom templates restored"
    else
      warn "Failed to restore custom templates"
      failed=1
    fi
  fi
  
  if [[ -d "${media_backup_dir}/certs" ]]; then
    if [[ -d "./certs" ]]; then
      rm -rf "./certs"
    fi
    if cp -r "${media_backup_dir}/certs" "./"; then
      log "✓ Certificates restored"
    else
      warn "Failed to restore certificates"
      failed=1
    fi
  fi
  
  chown -R 1000:1000 "./media" "./custom-templates" "./certs" 2>/dev/null || true
  
  if [[ $failed -eq 0 ]]; then
    log "✓ All media files restored successfully"
  else
    warn "Some media file restores failed"
  fi
  
  return $failed
}

start_services(){
  log "Starting Authentik services..."
  cd "${SCRIPT_DIR}"
  
  local dc=$(compose_cmd)
  if ${dc} up -d; then
    log "✓ Services started successfully"
  else
    error "Failed to start services"
    return 1
  fi
  
  log "Waiting for services to be ready..."
  sleep 10
  
  log "✓ Authentik restore completed successfully!"
  log "You can now access Authentik at the configured ports"
}

cleanup_restore_dir(){
  if [[ -d "$RESTORE_DIR" ]]; then
    log "Cleaning up temporary restore directory..."
    rm -rf "$RESTORE_DIR"
  fi
}

dry_run_restore(){
  local archive_path="$1"
  
  log "DRY RUN MODE - No actual changes will be made"
  echo
  
  if ! validate_backup_archive "$archive_path"; then
    return 1
  fi
  
  local backup_name
  backup_name=$(extract_backup_archive "$archive_path")
  
  show_backup_info "$backup_name"
  
  log "Would restore:"
  echo "  - PostgreSQL database from: ${RESTORE_DIR}/${backup_name}/postgres.sql"
  echo "  - Docker volumes from: ${RESTORE_DIR}/${backup_name}/volumes/"
  echo "  - Media files from: ${RESTORE_DIR}/${backup_name}/media/"
  echo "  - Environment configuration (.env) from: ${RESTORE_DIR}/${backup_name}/.env"
  echo
  log "Dry run completed - no changes made"
  
  cleanup_restore_dir
}

main(){
  local archive_path="$1"
  local dry_run=false
  local force=false
  
  shift
  while [[ $# -gt 0 ]]; do
    case $1 in
      --dry-run)
        dry_run=true
        shift
        ;;
      --force)
        force=true
        shift
        ;;
      --help|-h)
        show_usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
  done
  
  if [[ "$dry_run" == "true" ]]; then
    dry_run_restore "$archive_path"
    return $?
  fi
  
  if ! validate_backup_archive "$archive_path"; then
    exit 1
  fi
  
  log "Extracting backup archive..."
  local backup_name
  backup_name=$(extract_backup_archive "$archive_path")
  
  if [[ $? -eq 0 ]]; then
    log "✓ Backup archive extracted to: ${RESTORE_DIR}"
  else
    error "Failed to extract backup archive"
    exit 1
  fi
  
  show_backup_info "$backup_name"
  
  if [[ "$force" != "true" ]]; then
    confirm_restore "$backup_name"
  fi
  
  log "Starting Authentik restore process..."
  
  stop_services
  
  local restore_failed=0
  
  if ! restore_postgres "$backup_name"; then
    restore_failed=1
  fi
  
  if ! restore_volumes "$backup_name"; then
    restore_failed=1
  fi
  
  if ! restore_media_files "$backup_name"; then
    restore_failed=1
  fi
  
  if ! start_services; then
    restore_failed=1
  fi
  
  cleanup_restore_dir
  
  if [[ $restore_failed -eq 0 ]]; then
    log "✓ Authentik restore completed successfully!"
    echo
    echo -e "${GREEN}✓ Restore completed successfully!${NC}"
    echo -e "${BLUE}Authentik should now be running with restored data${NC}"
  else
    error "Restore completed with some errors - check logs above"
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  if [[ $# -eq 0 ]]; then
    show_usage
    exit 1
  fi
  
  main "$@"
fi
