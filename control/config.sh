#!/bin/bash

DEPLOY_HOSTNAME="$(hostname)"

USER_GID="${USER_GID:-$(id -g)}"
USER_UID=$(id -u)
DOCKER_GROUP="$(getent group docker | cut -d: -f3)"

VAULTWARDEN_DOMAIN="https://vault.aiemotion.net"
VAULTWARDEN_DATA_PATH="/vw-data"
VAULTWARDEN_PORT="8000"

declare -A services=(
  [webhook]="true"
  [mailserver]="true"
  [vaultwarden]="true"
)

declare -A service_groups=(
)

declare -A containers=(
  [webhook]="webhook"
  [vaultwarden]="vaultwarden"
)

declare -A images=(
  [webhook]="it-pal/webhook:latest"
  [mailserver]="it-pal/mailserver:latest"
  [vaultwarden]="vaultwarden/server:latest"
)

declare -A run_args=(
  [webhook]="-d --name ${containers[webhook]} \
    --restart unless-stopped \
    -v /etc/webhook:/etc/webhook \
    -v /var/dropbox:/var/dropbox \
    -p 127.0.0.1:9040:9000 \
    ${images[webhook]} \
    -verbose -debug -hooks=/etc/webhook/hooks.json -port 9000"
  [vaultwarden]="-d --name ${containers[vaultwarden]} \
    --restart unless-stopped \
    --env DOMAIN=\"${VAULTWARDEN_DOMAIN}\" \
    --volume ${VAULTWARDEN_DATA_PATH}:/data/ \
    --publish 127.0.0.1:${VAULTWARDEN_PORT}:80 \
    ${images[vaultwarden]}"
)

declare -A backup_services=(
  [mailserver]="weekly:30"
)

declare -A backup_s3_root=(
)

declare -A services_path=(
  [webhook]="/etc/webhook"
  [mailserver]="/etc/mailserver"
  [vaultwarden]="/etc/vaultwarden"
)

declare -A dependencies=(
)

declare -a start_order=(
  "mailserver"
  "vaultwarden"
  "webhook"
)

declare -a stop_order=(
  "mailserver"
  "vaultwarden"
  "webhook"
)

declare -A github_repos=(
  [webhook]="adnanh webhook master"
  [mailserver]="docker-mailserver docker-mailserver master"
)

declare -A skip_tags_releases=(
)

declare -A repos_path=(
  [webhook]="/etc/webhook/repo"
  [mailserver]="/etc/mailserver/repo"
)

declare -A build_contexts=(
  [webhook]="/etc/webhook/repo"
  [mailserver]="/etc/mailserver/repo"
)

declare -A build_args=(
)

declare -A dockerfiles=(
  [webhook]="/etc/webhook/Dockerfile"
  [mailserver]="/etc/mailserver/repo/Dockerfile"
)

declare -A use_buildkit=(
  [webhook]="true"
  [mailserver]="true"
)

# S3 Backup Configuration
BACKUP_S3_BUCKET="aiemotion-backup"
BACKUP_S3_REGION="ap-southeast-1"
BACKUP_AWS_PROFILE="aiemotion-backup"
