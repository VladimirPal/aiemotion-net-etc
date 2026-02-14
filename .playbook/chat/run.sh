#@ssh host=root.aiemotion.net

#@group "Build Chat Services"

#@step "Build MAS"
scs build mas

#@step "Build Synapse"
scs build synapse

#@step "Build Element Web"
scs build element-web-builder

#@group "Service management"

#@step "List Chat Services"
scs list-services

#@step "Start Element Web build"
scs start element-web-builder

#@step "Check Chat Services Status"
scs status chat

#@step "Restart Chat Services"
scs restart chat

#@step "Stop All Services"
scs stop all

#@group "Nginx"

#@step "Restart Nginx"
systemctl restart nginx

#@group "MAS"

#@step "Restart MAS"
scs restart mas

#@step "Sync MAS Config"
docker exec devchat_chat_mas mas-cli config sync --prune -c /config.yaml

#@step "Show MAS Logs"
scs logs mas

#@group "Synapse"

#@step "Restart Synapse"
scs restart synapse

#@step "Show Synapse Logs"
scs logs synapse

#@group "Manage Chat script"

#@step "Register Admin User"
#@env USER_NAME="admin"
#@env USER_PASSWORD=
./manage-chat.sh register-user \
  "$USER_NAME" "$USER_PASSWORD" "$USER_NAME@devchat.internal" "$USER_NAME" admin

#@step "Register test user"
#@env TEST_USER_NAME="test"
#@env TEST_USER_PASSWORD=
./manage-chat.sh register-user \
  "$TEST_USER_NAME" "$TEST_USER_PASSWORD" "$TEST_USER_NAME@devchat.internal" "$TEST_USER_NAME" admin

#@step "List Admin Users"
./manage-chat.sh list-admin-users

#@step "Show Chat Status"
./manage-chat.sh status

#@step "Open Chat in Browser"
echo "Opening Chat in Browser..."
xdg-open https://element.devchat.internal

#@group "Chat Services"
#@target root.apps.it-pal.net

#@step "Show status of chat services"
scs status chat

#@step "Restart all chat services"
scs restart chat

#@group "Synapse"
#@target root.apps.it-pal.net

#@step "Status of Synapse"
scs status synapse

#@step "Check for updates for Synapse"
scs check-update synapse

#@step "Backup Synapse"
scs backup synapse

#@step "Upgrade Synapse to the latest version"
scs upgrade synapse

#@step "View Synapse service logs"
scs logs synapse

#@group "Matrix Authenticator Service (MAS)"
#@target root.apps.it-pal.net

#@step "Status of MAS"
scs status mas

#@step "Restart MAS"
scs restart mas

#@step "Check for updates for MAS"
scs check-update mas

#@step "Backup MAS"
scs backup mas

#@step "Upgrade MAS to the latest version"
scs upgrade mas

#@step "Look at MAS service logs"
scs logs mas

#@group "Element Web"
#@target root.apps.it-pal.net

#@step "Check for updates for Element Web"
scs check-update element-web-builder

#@step "Upgrade Element Web to the latest version"
scs upgrade element-web-builder

#@step "Build Element Web image"
scs build element-web-builder

#@step "Restart Element Web build"
scs restart element-web-builder

#@group "S3 Provider"
#@target root.apps.it-pal.net

#@step "Check for updates for S3 provider"
scs check-update s3provider

#@step "Upgrade S3 provider to the latest version"
scs upgrade s3provider
