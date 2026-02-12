#!/bin/bash

DEPLOY_HOSTNAME="$(hostname)"

USER_GID="${USER_GID:-$(id -g)}"
USER_UID=$(id -u)
DOCKER_GROUP="$(getent group docker | cut -d: -f3)"

declare -A services=(
  [webhook]="true"
  [mailserver]="true"
)

declare -A service_groups=(
)

declare -A containers=(
  [webhook]="webhook"
)

declare -A images=(
  [webhook]="webhook-it-pal:latest"
  [mailserver]="it-pal/mailserver:latest"
)

declare -A run_args=(
  [webhook]="-d --name ${containers[webhook]} \
    --restart unless-stopped \
    -v /etc/webhook:/etc/webhook \
    -v /var/dropbox:/var/dropbox \
    -p 127.0.0.1:9040:9000 \
    ${images[webhook]} \
    -verbose -debug -hooks=/etc/webhook/hooks.json -port 9000"
)

declare -A backup_services=(
  [mailserver]="weekly:30"
)

declare -A backup_s3_root=(
)

declare -A services_path=(
  [webhook]="/etc/webhook"
  [mailserver]="/etc/mailserver"
)

declare -A dependencies=(
)

declare -a start_order=(
  "mailserver"
  "webhook"
)

declare -a stop_order=(
  "mailserver"
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
