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

#@group "Initial Setup"
#@step "Create authentik mailbox account"
#@env MAIL_AUTHENTIK_ACCOUNT=authentik@aiemotion.net
#@env MAIL_AUTHENTIK_PASSWORD=
docker exec mailserver setup email add "${MAIL_AUTHENTIK_ACCOUNT}" "${MAIL_AUTHENTIK_PASSWORD}"
echo "Authentik mailbox account created: ${MAIL_AUTHENTIK_ACCOUNT}"

#@step "Generate authentik secrets (PG_PASS and AUTHENTIK_SECRET_KEY)"
PG_PASS="$(openssl rand -base64 48 | tr -d '\n')"
AUTHENTIK_SECRET_KEY="$(openssl rand -base64 72 | tr -d '\n')"
echo "PG_PASS=${PG_PASS}"
echo "AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}"

#@step "Apply Route53 A record for Authentik domain (id.aiemotion.net)"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env ROUTE53_TTL=300
#@env AUTHENTIK_DOMAIN=id.aiemotion.net
#@env AUTHENTIK_IPV4=157.180.4.111
. ".playbook/lib/mailserver.sh"
init_aws_cmd

add_a_record "${ROUTE53_HOSTED_ZONE_ID}" "${AUTHENTIK_DOMAIN}" "${AUTHENTIK_IPV4}" || exit 1

#@step "Verify Authentik DNS A record"
#@env AUTHENTIK_DOMAIN=id.aiemotion.net
#@env AUTHENTIK_IPV4=157.180.4.111
. ".playbook/lib/mailserver.sh"

verify_dns_contains "A" "${AUTHENTIK_DOMAIN%.}" "${AUTHENTIK_IPV4}" || exit 1

#@group "Nginx + Let's Encrypt for Authentik"
#@env AUTHENTIK_DOMAIN=id.aiemotion.net
#@env LETSENCRYPT_EMAIL=admin@aiemotion.net
#@env CERTBOT_WEBROOT=/var/www/letsencrypt
#@env AUTHENTIK_NGINX_CONF=/etc/nginx/conf.d/id.aiemotion.net.conf

#@step "Install Certbot for Let's Encrypt"
apt-get update -y
apt-get install -y certbot
certbot --version

#@step "Enable and start certbot.timer for automatic renewal"
systemctl enable --now certbot.timer
systemctl status certbot.timer --no-pager

#@step "Issue/Renew Let's Encrypt certificate for Authentik domain"
certbot certonly --webroot \
  -w "${CERTBOT_WEBROOT}" \
  --non-interactive \
  --agree-tos \
  --email "${LETSENCRYPT_EMAIL}" \
  --keep-until-expiring \
  -d "${AUTHENTIK_DOMAIN}"

if [ ! -s "/etc/letsencrypt/live/${AUTHENTIK_DOMAIN}/fullchain.pem" ] || [ ! -s "/etc/letsencrypt/live/${AUTHENTIK_DOMAIN}/privkey.pem" ]; then
  echo "Let's Encrypt certificate files not found for ${AUTHENTIK_DOMAIN}."
  exit 1
fi

#@step "Ensure recommended Let's Encrypt SSL options files exist"
if [ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
  echo "Downloading /etc/letsencrypt/options-ssl-nginx.conf ..."
  curl -fsSL \
    https://raw.githubusercontent.com/certbot/certbot/master/certbot-nginx/certbot_nginx/_internal/tls_configs/options-ssl-nginx.conf \
    -o /etc/letsencrypt/options-ssl-nginx.conf
fi
echo "Ready: /etc/letsencrypt/options-ssl-nginx.conf"

if [ ! -f /etc/letsencrypt/ssl-dhparams.pem ]; then
  echo "Downloading /etc/letsencrypt/ssl-dhparams.pem ..."
  curl -fsSL \
    https://raw.githubusercontent.com/certbot/certbot/master/certbot/certbot/ssl-dhparams.pem \
    -o /etc/letsencrypt/ssl-dhparams.pem
fi
echo "Ready: /etc/letsencrypt/ssl-dhparams.pem"

#@step "Verify automatic renewal with certbot dry-run"
certbot renew --dry-run

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
