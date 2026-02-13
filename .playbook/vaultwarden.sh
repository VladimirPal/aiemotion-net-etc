#@ssh host=root.aiemotion.net

#@group "Manage vaultwarden"
#@step "Show running vaultwarden docker container"
docker ps --filter "name=vaultwarden"

#@step "View vaultwarden docker container logs"
docker logs --tail 200 vaultwarden

#@step "Status of vaultwarden service"
scs status vaultwarden

#@step "View vaultwarden service logs"
scs logs vaultwarden

#@step "Restart vaultwarden service"
scs restart vaultwarden

#@step "Stop vaultwarden service"
scs stop vaultwarden

#@step "Start vaultwarden service"
scs start vaultwarden

#@step "Pull latest vaultwarden image"
docker pull vaultwarden/server:latest

#@step "Upgrade vaultwarden to the latest container image"
docker pull vaultwarden/server:latest
scs restart vaultwarden

#@group "Install"
#@step "Create persistent data and service directories"
#@env VAULTWARDEN_DATA_PATH=/vw-data
mkdir -p "${VAULTWARDEN_DATA_PATH}" /etc/vaultwarden
chmod 700 "${VAULTWARDEN_DATA_PATH}"
