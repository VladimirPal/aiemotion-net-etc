#!/bin/bash

DEPLOY_HOSTNAME="$(hostname)"

USER_GID="${USER_GID:-$(id -g)}"
USER_UID=$(id -u)
DOCKER_GROUP="$(getent group docker | cut -d: -f3)"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHAT_NETWORK="chat"

POSTGRES_SYNAPSE_USER="synapse_user"
POSTGRES_SYNAPSE_PASSWORD="synapse_password"
POSTGRES_SYNAPSE_DB="synapse"

VAULTWARDEN_DOMAIN="https://vault.aiemotion.net"
VAULTWARDEN_DATA_PATH="/vw-data"
VAULTWARDEN_PORT="8000"
VAULTWARDEN_ADMIN_TOKEN_HASH="${VAULTWARDEN_ADMIN_TOKEN_HASH-}"
# scs executes docker run via eval; escape '$' so Argon2 PHC survives intact.
VAULTWARDEN_ADMIN_TOKEN_HASH_ESCAPED="${VAULTWARDEN_ADMIN_TOKEN_HASH//$/\\$}"
VAULTWARDEN_SSO_ENABLED="${VAULTWARDEN_SSO_ENABLED:-true}"
VAULTWARDEN_SSO_ONLY="${VAULTWARDEN_SSO_ONLY:-true}"
VAULTWARDEN_SSO_SIGNUPS_MATCH_EMAIL="${VAULTWARDEN_SSO_SIGNUPS_MATCH_EMAIL:-true}"
VAULTWARDEN_SSO_CLIENT_CACHE_EXPIRATION="${VAULTWARDEN_SSO_CLIENT_CACHE_EXPIRATION:-600}"
AUTHENTIK_DOMAIN="${AUTHENTIK_DOMAIN:-id.aiemotion.net}"
AUTHENTIK_VAULTWARDEN_APP_SLUG="${AUTHENTIK_VAULTWARDEN_APP_SLUG:-vaultwarden}"
VAULTWARDEN_SSO_AUTHORITY="${VAULTWARDEN_SSO_AUTHORITY:-https://${AUTHENTIK_DOMAIN}/application/o/${AUTHENTIK_VAULTWARDEN_APP_SLUG}/}"
VAULTWARDEN_SSO_SCOPES="${VAULTWARDEN_SSO_SCOPES:-email vaultwarden-email profile offline_access}"
VAULTWARDEN_SSO_CLIENT_ID="${VAULTWARDEN_SSO_CLIENT_ID-}"
VAULTWARDEN_SSO_CLIENT_SECRET="${VAULTWARDEN_SSO_CLIENT_SECRET-}"

DOCUSAURUS_ARGS="--rm -it \
  -v /etc/docusaurus:/app \
  -v /etc/control/docs/memory-alive-docs:/app/docs/memory-alive-docs"

declare -A services=(
  [authentik]="true"
  [webhook]="true"
  [mailserver]="true"
  [vaultwarden]="true"
  ["docusaurus-builder"]="true"
  ["element-web-builder"]="true"
  ["postgresql-chat"]="true"
  [synapse]="true"
  [mas]="true"
)

declare -A service_groups=(
  [chat]="synapse mas"
)

declare -A containers=(
  [webhook]="webhook"
  [vaultwarden]="vaultwarden"
  ["docusaurus-builder"]="docusaurus-builder"
  ["element-web-builder"]="element-web-builder"
  ["postgresql-chat"]="postgresql-chat"
  [synapse]="synapse"
  [mas]="mas"
)

declare -A images=(
  [webhook]="it-pal/webhook:latest"
  [mailserver]="it-pal/mailserver:latest"
  [vaultwarden]="vaultwarden/server:latest"
  ["docusaurus-builder"]="it-pal/docusaurus-builder:latest"
  ["element-web-builder"]="it-pal/element-web-builder:latest"
  ["postgresql-chat"]="postgres:18-alpine"
  [synapse]="it-pal/synapse:latest"
  [mas]="it-pal/mas:latest"
)

declare -A run_args=(
  [webhook]="-d --name ${containers[webhook]} \
    --restart unless-stopped \
    -v /etc/webhook:/etc/webhook \
    -v /var/dropbox:/var/dropbox \
    -p 127.0.0.1:9040:9000 \
    ${images[webhook]} \
    -verbose -debug -hooks=/etc/webhook/hooks.json -port 9000"
  [synapse]="-d --name ${containers[synapse]} \
    --network $CHAT_NETWORK \
    --restart unless-stopped \
    -e AWS_SHARED_CREDENTIALS_FILE=/data/.aws-credentials \
    -e AWS_PROFILE=synapse-media \
    --mount type=bind,src=/etc/chat/synapse,dst=/data \
    -v=/etc/chat/synapse/keys:/data/keys \
    -v=/etc/chat/synapse/s3provider/repo:/opt/synapse-s3-storage-provider \
    --entrypoint /bin/bash \
    -p 127.0.0.1:8008:8008 \
    ${images[synapse]} \
    -lc \"python3 -m pip install /opt/synapse-s3-storage-provider && exec python3 /start.py\""
  [mas]="-d --name ${containers[mas]} \
    --network $CHAT_NETWORK \
    --restart unless-stopped \
    -v=/etc/chat/mas/ssh/id_rsa.pub:/tmp/authorized_keys \
    -v=/etc/chat/mas/config.yaml:/config.yaml \
    -v=/etc/chat/mas/enc_key.pem:/enc_key.pem \
    -v=/etc/chat/mas/keys:/keys \
    -p 127.0.0.1:8080:8080 -p 127.0.0.1:8081:8081 \
    ${images[mas]}"
  [vaultwarden]="-d --name ${containers[vaultwarden]} \
    --restart unless-stopped \
    --env DOMAIN=\"${VAULTWARDEN_DOMAIN}\" \
    --env SIGNUPS_ALLOWED=false \
    --env INVITATIONS_ALLOWED=false \
    --env ADMIN_TOKEN=\"${VAULTWARDEN_ADMIN_TOKEN_HASH_ESCAPED}\" \
    --env SSO_ENABLED=\"${VAULTWARDEN_SSO_ENABLED}\" \
    --env SSO_ONLY=\"${VAULTWARDEN_SSO_ONLY}\" \
    --env SSO_SIGNUPS_MATCH_EMAIL=\"${VAULTWARDEN_SSO_SIGNUPS_MATCH_EMAIL}\" \
    --env SSO_AUTHORITY=\"${VAULTWARDEN_SSO_AUTHORITY}\" \
    --env SSO_SCOPES=\"${VAULTWARDEN_SSO_SCOPES}\" \
    --env SSO_CLIENT_ID=\"${VAULTWARDEN_SSO_CLIENT_ID}\" \
    --env SSO_CLIENT_SECRET=\"${VAULTWARDEN_SSO_CLIENT_SECRET}\" \
    --env SSO_CLIENT_CACHE_EXPIRATION=\"${VAULTWARDEN_SSO_CLIENT_CACHE_EXPIRATION}\" \
    --volume ${VAULTWARDEN_DATA_PATH}:/data/ \
    --publish 127.0.0.1:${VAULTWARDEN_PORT}:80 \
    ${images[vaultwarden]}"
  ["postgresql-chat"]="-d --name ${containers["postgresql-chat"]} \
    --network $CHAT_NETWORK \
    --restart unless-stopped \
    -v=postgresql-chat-data:/var/lib/postgresql/data \
    -e POSTGRES_USER=$POSTGRES_SYNAPSE_USER \
    -e POSTGRES_PASSWORD=$POSTGRES_SYNAPSE_PASSWORD \
    -e POSTGRES_DB=$POSTGRES_SYNAPSE_DB \
    -e POSTGRES_INITDB_ARGS='--encoding=UTF8 --locale=C' \
    -e LC_COLLATE=C \
    -e LC_CTYPE=C \
    ${images["postgresql-chat"]}"
  ["docusaurus-builder"]="$DOCUSAURUS_ARGS \
    \${images["docusaurus-builder"]} \
    bash -c \"npm install && npm run build\""
)

declare -A backup_services=(
  [authentik]="monthly:90"
  [mailserver]="weekly:30"
  [synapse]="weekly:30"
  [mas]="weekly:30"
)

declare -A backup_s3_root=(
  [mailserver]="mail.aiemotion.net"
)

declare -A services_path=(
  [authentik]="/etc/authentik"
  [webhook]="/etc/webhook"
  [mailserver]="/etc/mailserver"
  [vaultwarden]="/etc/vaultwarden"
  ["docusaurus-builder"]="/etc/docusaurus"
  ["element-web-builder"]="/etc/chat/element-web"
  ["postgresql-chat"]="/etc/chat/postgresql"
  [synapse]="/etc/chat/synapse"
  [mas]="/etc/chat/mas"
)

declare -A dependencies=(
  [synapse]="postgresql-chat"
  [mas]="postgresql-chat synapse"
)

declare -a start_order=(
  "authentik"
  "postgresql-chat"
  "synapse"
  "mas"
  "mailserver"
  "vaultwarden"
  "webhook"
)

declare -a stop_order=(
  "mailserver"
  "vaultwarden"
  "webhook"
  "mas"
  "synapse"
  "postgresql-chat"
)

declare -A github_repos=(
  [webhook]="adnanh webhook master"
  [mailserver]="docker-mailserver docker-mailserver master"
  ["docusaurus-builder"]="facebook docusaurus main"
  ["element-web-builder"]="element-hq element-web develop"
  [synapse]="element-hq synapse develop"
  [mas]="element-hq matrix-authentication-service main"
)

declare -A skip_tags_releases=(
)

declare -A repos_path=(
  [webhook]="/etc/webhook/repo"
  [mailserver]="/etc/mailserver/repo"
  ["element-web-builder"]="/etc/chat/element-web/repo"
  [synapse]="/etc/chat/synapse/repo"
  [mas]="/etc/chat/mas/repo"
)

declare -A build_contexts=(
  [webhook]="/etc/webhook/repo"
  [mailserver]="/etc/mailserver/repo"
  ["docusaurus-builder"]="/etc/docusaurus"
  ["element-web-builder"]="/etc/chat/element-web/repo"
  [synapse]="/etc/chat/synapse/repo"
  [mas]="/etc/chat/mas/repo"
)

declare -A build_args=(
  [mas]="--ulimit memlock=8388608:8388608 --ulimit nofile=524288:524288"
)

declare -A dockerfiles=(
  [webhook]="/etc/webhook/Dockerfile"
  [mailserver]="/etc/mailserver/repo/Dockerfile"
  ["docusaurus-builder"]="/etc/docusaurus/Dockerfile"
  ["element-web-builder"]="/etc/chat/element-web/Dockerfile"
  [synapse]="/etc/chat/synapse/Dockerfile"
  [mas]="/etc/chat/mas/Dockerfile"
)

declare -A use_buildkit=(
  [webhook]="true"
  [mailserver]="true"
  ["docusaurus-builder"]="true"
  ["element-web-builder"]="true"
  [synapse]="true"
  [mas]="true"
)

# S3 Backup Configuration
BACKUP_S3_BUCKET="aiemotion-backup"
BACKUP_S3_REGION="ap-southeast-1"
BACKUP_AWS_PROFILE="aiemotion-backup"

create_network() {
  if ! docker network ls | grep -q "$CHAT_NETWORK"; then
    echo "🌐 Creating Docker network $CHAT_NETWORK..."
    docker network create "$CHAT_NETWORK"
  fi
}

create_network
