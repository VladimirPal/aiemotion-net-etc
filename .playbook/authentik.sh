#@ssh host=root.aiemotion.net

#@group "Manage authentik Service"

#@step "Status of authentik service"
scs status authentik

#@step "Restart authentik service"
scs restart authentik

#@step "View authentik service logs"
scs logs authentik

#@step "Check for updates for authentik"
scs check-update authentik

#@step "Backup authentik"
scs backup authentik

#@step "Upgrade authentik to the latest version"
scs upgrade authentik

#@step "Create authentik mailbox account (if needed)"
#@env MAIL_AUTHENTIK_ACCOUNT=authentik@aiemotion.net
#@env MAIL_AUTHENTIK_PASSWORD=
docker exec mailserver setup email add "${MAIL_AUTHENTIK_ACCOUNT}" "${MAIL_AUTHENTIK_PASSWORD}"
echo "Authentik mailbox account created: ${MAIL_AUTHENTIK_ACCOUNT}"

#@step "Generate authentik secrets (PG_PASS and AUTHENTIK_SECRET_KEY)"
PG_PASS="$(openssl rand -base64 48 | tr -d '\n')"
AUTHENTIK_SECRET_KEY="$(openssl rand -base64 72 | tr -d '\n')"
echo "PG_PASS=${PG_PASS}"
echo "AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}"

#@group "Backup and Autostart Setup for authentik"

#@step "Setup authentik backup service and timer"
scs setup-backup authentik

#@step "Status of authentik backup service and timer"
systemctl status scs-backup-authentik.service
systemctl status scs-backup-authentik.timer

#@step "Start authentik backup service manually"
systemctl start scs-backup-authentik.service

#@step "View logs of authentik backup service"
journalctl -u scs-backup-authentik.service

#@step "Status of authentik autostart service"
systemctl status scs-autostart-authentik.service

#@step "Setup authentik autostart service"
scs autostart authentik

#@group "Adminctl"

#@step "Subscribe to authentik adminctl Redis channel"
redis-cli -h 127.0.0.1 -p 6380 SUBSCRIBE adminctl

#@step "Get authentik version"
/usr/local/bin/adminctl --verbose authentik version

#@step "Check for authentik updates"
/usr/local/bin/adminctl authentik check-update

#@step "Upgrade authentik to the latest version"
/usr/local/bin/adminctl authentik upgrade
