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

#@group "Initial Setup"

#@step "Apply Route53 A record for Vaultwarden domain (vault.aiemotion.net)"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env ROUTE53_TTL=300
#@env VAULTWARDEN_DOMAIN=vault.aiemotion.net
#@env VAULTWARDEN_IPV4=157.180.4.111
. ".playbook/lib/mailserver.sh"
init_aws_cmd

add_a_record "${ROUTE53_HOSTED_ZONE_ID}" "${VAULTWARDEN_DOMAIN}" "${VAULTWARDEN_IPV4}" || exit 1

#@step "Verify Vaultwarden DNS A record"
#@env VAULTWARDEN_DOMAIN=vault.aiemotion.net
#@env VAULTWARDEN_IPV4=157.180.4.111
. ".playbook/lib/mailserver.sh"

verify_dns_contains "A" "${VAULTWARDEN_DOMAIN%.}" "${VAULTWARDEN_IPV4}" || exit 1

#@group "Nginx + Let's Encrypt for Vaultwarden"
#@env VAULTWARDEN_DOMAIN=vault.aiemotion.net
#@env LETSENCRYPT_EMAIL=admin@aiemotion.net
#@env CERTBOT_WEBROOT=/var/www/letsencrypt
#@env VAULTWARDEN_NGINX_CONF=/etc/nginx/conf.d/vault.aiemotion.net.conf

#@step "Install Certbot for Let's Encrypt"
apt-get update -y
apt-get install -y certbot
certbot --version

#@step "Enable and start certbot.timer for automatic renewal"
systemctl enable --now certbot.timer
systemctl status certbot.timer --no-pager

#@step "Issue/Renew Let's Encrypt certificate for Vaultwarden domain"
certbot certonly --webroot \
  -w "${CERTBOT_WEBROOT}" \
  --non-interactive \
  --agree-tos \
  --email "${LETSENCRYPT_EMAIL}" \
  --keep-until-expiring \
  -d "${VAULTWARDEN_DOMAIN}"

if [ ! -s "/etc/letsencrypt/live/${VAULTWARDEN_DOMAIN}/fullchain.pem" ] || [ ! -s "/etc/letsencrypt/live/${VAULTWARDEN_DOMAIN}/privkey.pem" ]; then
  echo "Let's Encrypt certificate files not found for ${VAULTWARDEN_DOMAIN}."
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
