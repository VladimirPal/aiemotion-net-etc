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
  chmod 777 "${BACKUP_DIR}" || true;
  chown 1000:1000 "${BACKUP_DIR}" 2>/dev/null || true;
}

project_name_from_env(){
  local f="${1}"
  if [[ -f "$f" ]]; then
    grep -E '^[[:space:]]*COMPOSE_PROJECT_NAME=' "$f" | tail -n1 | cut -d= -f2- | tr -d '"' | tr -d '\r' | xargs || true
  fi
}

compose_cmd(){ echo "docker compose --env-file ${SCRIPT_DIR}/.env -f ${SCRIPT_DIR}/docker-compose.yml"; }

perform_postgres_backup(){
  log "Starting PostgreSQL database backup..."
  cd "${SCRIPT_DIR}"

  local backup_dir="${BACKUP_DIR}/${BACKUP_NAME}"
  mkdir -p "${backup_dir}"
  local db_backup_file="${backup_dir}/postgres.sql"
  
  if docker compose exec -T postgresql pg_dump -U authentik -d authentik > "${db_backup_file}"; then
    log "PostgreSQL backup completed: ${db_backup_file}"
    chmod 0640 "${db_backup_file}" || true
  else
    error "PostgreSQL backup failed"
    return 1
  fi
}

collect_volumes(){
  local pn="$1"
  
  cd "${SCRIPT_DIR}"
  local dc=$(compose_cmd)
  
  local volumes
  volumes=$(${dc} config --volumes 2>/dev/null || true)
  
  if [[ -z "$volumes" ]]; then
    warn "No volumes found in docker-compose configuration"
    return 0
  fi
  
  local critical_volumes
  critical_volumes=$(echo "$volumes" | grep -E "(database|redis)" | sed "s/^/${pn}_/" || true)
  
  if [[ -n "$critical_volumes" ]]; then
    echo "$critical_volumes"
  else
    warn "No critical volumes found to backup"
  fi
}

perform_full_backup(){
  log "Starting full backup of Docker volumes..."
  cd "${SCRIPT_DIR}"

  local dc=$(compose_cmd)
  local project_name
  project_name=$(project_name_from_env "${SCRIPT_DIR}/.env")
  if [[ -z "${project_name}" ]]; then project_name="authentik"; fi

  local backup_dir="${BACKUP_DIR}/${BACKUP_NAME}"
  local full_backup_dir="${backup_dir}/volumes"
  mkdir -p "${full_backup_dir}"

  local services_stopped=0
  trap 'rc=$?; exit ${rc}' EXIT

  log "Stopping all services for consistent volume backup..."
  ${dc} stop || true
  services_stopped=1

  local failed=0
  while IFS= read -r volume; do
    if [[ -z "${volume}" ]]; then continue; fi
    if docker volume inspect "${volume}" >/dev/null 2>&1; then
      log "Backing up volume: ${volume}"
      local outfile="${full_backup_dir}/${volume}.tar.gz"
      if docker run --rm -v "${volume}:/data:ro" -v "${full_backup_dir}:/backup" alpine \
         tar czf "/backup/${volume}.tar.gz" -C /data .; then
        log "✓ ${volume} backed up"
      else
        warn "Failed to backup volume: ${volume}"
        failed=1
      fi
    else
      warn "Volume ${volume} not found, skipping"
    fi
  done < <(collect_volumes "${project_name}")

  chown -R "$(id -u):$(id -g)" "${full_backup_dir}" || true
  log "Full backup directory: ${full_backup_dir}"
  return ${failed}
}

backup_media_files(){
  log "Backing up Authentik media files..."
  cd "${SCRIPT_DIR}"

  local backup_dir="${BACKUP_DIR}/${BACKUP_NAME}"
  local media_backup_dir="${backup_dir}/media"
  mkdir -p "${media_backup_dir}"

  if [[ -d "./media" ]]; then
    if cp -r "./media" "${media_backup_dir}/"; then
      log "✓ Media files backed up"
    else
      warn "Failed to backup media files"
      return 1
    fi
  else
    warn "Media directory not found, skipping"
  fi

  if [[ -d "./custom-templates" ]]; then
    if cp -r "./custom-templates" "${media_backup_dir}/"; then
      log "✓ Custom templates backed up"
    else
      warn "Failed to backup custom templates"
      return 1
    fi
  else
    warn "Custom templates directory not found, skipping"
  fi

  if [[ -d "./certs" ]]; then
    if cp -r "./certs" "${media_backup_dir}/"; then
      log "✓ Certificates backed up"
    else
      warn "Failed to backup certificates"
      return 1
    fi
  else
    warn "Certificates directory not found, skipping"
  fi

  # Backup .env file (critical for configuration)
  if [[ -f "./.env" ]]; then
    if cp "./.env" "${backup_dir}/"; then
      log "✓ Environment configuration (.env) backed up"
    else
      warn "Failed to backup .env file"
      return 1
    fi
  else
    warn ".env file not found, skipping"
  fi

  chown -R "$(id -u):$(id -g)" "${media_backup_dir}" || true
  log "Media backup directory: ${media_backup_dir}"
}

create_backup_manifest(){
  local backup_dir="${BACKUP_DIR}/${BACKUP_NAME}"
  local manifest_file="${backup_dir}/manifest.txt"
  
  local docker_image_ids
  docker_image_ids=$(
    cd "${SCRIPT_DIR}" && \
    docker compose config --format json | \
    jq -r '.services[].image' | \
    sort -u | \
    while read -r image; do
      if [[ -n "$image" && "$image" != "null" ]]; then
        docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" | \
        grep "^${image} " | \
        head -1
      fi
    done | \
    grep -v "^$" || \
    echo "Unable to get image IDs"
  )

  {
    echo "Authentik Self-Hosted Backup Manifest"
    echo "====================================="
    echo "Backup Date: $(date)"
    echo "DatePrefix: ${TIMESTAMP}"
    echo "Backup Name: ${BACKUP_NAME}"
    echo "Backup Type: Combined (PostgreSQL + Redis + Media Files)"
    echo
    if [[ -f "${backup_dir}/postgres.sql" ]]; then
      echo "PostgreSQL Backup: ${backup_dir}/postgres.sql"
    else
      echo "PostgreSQL Backup: MISSING"
    fi
    echo "Redis Backup: Via volume backup (authentik_redis)"
    echo "Media Backup Directory: ${backup_dir}/media"
    echo "Full Backup Directory: ${backup_dir}/volumes"
    echo
    echo "Volumes Backed Up:"
    collect_volumes "$(project_name_from_env "${SCRIPT_DIR}/.env" || echo authentik)" | sed 's/^/- /'
    echo
    echo "Backup Script: ${SCRIPT_DIR}/backup.sh"
    echo
    echo "Docker Image IDs (for exact restoration):"
    echo "${docker_image_ids}" | sed 's/^/- /'
    echo
    echo "Notes:"
    echo "- PostgreSQL backup contains users, applications, policies, and configurations"
    echo "- Redis data backed up via volume (authentik_redis) - contains session data and cache"
    echo "- Media files include uploaded files, custom templates, and certificates"
    echo "- Environment configuration (.env) includes database credentials and secret keys"
    echo "- Volume backup contains critical persistent data (postgres, redis)"
    echo "- IMPORTANT: Use Docker Image IDs to restore to exactly the same images"
    echo "- If image IDs differ, consider pulling the exact images before restore"
    echo "- Ensure all services are stopped before restore"
    echo "- Authentik secret key and database credentials are in .env file"
  } > "${manifest_file}"

  log "Backup manifest created: ${manifest_file}"
  
  # Print manifest contents to log
  log "Backup Manifest Contents:"
  echo -e "${BLUE}----------------------------------------${NC}"
  cat "${manifest_file}" | sed 's/^/  /'
  echo -e "${BLUE}----------------------------------------${NC}"
}

create_final_archive(){
  log "Creating final backup archive..."
  cd "${BACKUP_DIR}"
  
  local archive_name="${BACKUP_NAME}.tar.gz"
  
  if tar -czf "${archive_name}" "${BACKUP_NAME}" 2>/dev/null; then
    log "Final backup archive created: ${archive_name}"
    
    rm -rf "${BACKUP_NAME}"
    log "Individual backup files cleaned up"
  else
    warn "Failed to create final archive, keeping individual files"
  fi
}

main(){
  create_backup_dir
  log "Starting Authentik self-hosted backup"
  log "Backup name: ${BACKUP_NAME}"

  if ! perform_postgres_backup; then
    error "PostgreSQL backup failed"
    exit 1
  fi

  if ! perform_full_backup; then
    warn "One or more volume backups failed"
  fi

  if ! backup_media_files; then
    warn "Media files backup failed"
  fi

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
    echo "  - PostgreSQL database backup via pg_dump"
    echo "  - Redis data backup via volume snapshot"
    echo "  - Media files backup (uploads, templates, certificates)"
    echo "  - Full tar.gz snapshots of critical Docker volumes"
    echo "Outputs: Single .tar.gz archive in backups/ directory"
    echo "SCS handles: S3 upload, retention, service restart"
    ;;
  *)
    main
    ;;
esac