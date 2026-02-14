#@ssh host=root.aiemotion.net

#@group "Route53 DNS for matrix-auth.aiemotion.net"

#@step "Register matrix-auth.aiemotion.net CNAME record"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env ROUTE53_TTL=300
#@env MATRIX_AUTH_DOMAIN=matrix-auth.aiemotion.net
#@env MATRIX_AUTH_TARGET_DOMAIN=root.aiemotion.net
. ".playbook/lib/chat.sh"
init_aws_cmd

matrix_auth_domain="${MATRIX_AUTH_DOMAIN}"
matrix_auth_target_domain="${MATRIX_AUTH_TARGET_DOMAIN%.}."
route53_zone_id="${ROUTE53_HOSTED_ZONE_ID}"
route53_ttl="${ROUTE53_TTL}"

tmp_change_batch="$(mktemp)"
cleanup() {
  rm -f "${tmp_change_batch}"
}
trap cleanup EXIT

cat >"${tmp_change_batch}" <<EOF
{
  "Comment": "UPSERT CNAME ${matrix_auth_domain} -> ${matrix_auth_target_domain}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${matrix_auth_domain%.}.",
        "Type": "CNAME",
        "TTL": ${route53_ttl},
        "ResourceRecords": [{ "Value": "${matrix_auth_target_domain}" }]
      }
    }
  ]
}
EOF

"${CHAT_AWS_CMD[@]}" route53 change-resource-record-sets \
  --hosted-zone-id "${route53_zone_id}" \
  --change-batch "file://${tmp_change_batch}" >/dev/null

log_ok "Route53 record registered: ${matrix_auth_domain} -> ${matrix_auth_target_domain}"

#@group "Nginx + Let's Encrypt for matrix-auth.aiemotion.net"

#@env MATRIX_AUTH_DOMAIN=matrix-auth.aiemotion.net
#@env MATRIX_AUTH_NGINX_CONF=/etc/nginx/conf.d/matrix-auth.aiemotion.net.conf
#@env MATRIX_AUTH_NGINX_BOOTSTRAP_SOURCE=nginx/bootstrap/matrix-auth.aiemotion.net.conf
#@env MATRIX_AUTH_NGINX_TLS_SOURCE=nginx/conf.d/matrix-auth.aiemotion.net.conf
#@env LETSENCRYPT_EMAIL=admin@aiemotion.net
#@env CERTBOT_WEBROOT=/var/www/letsencrypt

#@step "Ensure Nginx is installed and running"
apt-get update -y
apt-get install -y nginx
systemctl enable --now nginx
systemctl status nginx --no-pager

#@step "Install bootstrap Nginx config for ACME and MAS proxy"
resolve_conf_source() {
  conf_path="$1"
  conf_path="${conf_path#./}"

  if [ -f "$1" ]; then
    printf '%s\n' "$1"
    return 0
  fi

  if [ -f "${conf_path}" ]; then
    printf '%s\n' "${conf_path}"
    return 0
  fi

  if [ -f "/etc/control/${conf_path}" ]; then
    printf '%s\n' "/etc/control/${conf_path}"
    return 0
  fi

  return 1
}

mkdir -p "${CERTBOT_WEBROOT}"
bootstrap_source="$(resolve_conf_source "${MATRIX_AUTH_NGINX_BOOTSTRAP_SOURCE}")"
if [ -z "${bootstrap_source}" ]; then
  echo "Bootstrap Nginx config not found: ${MATRIX_AUTH_NGINX_BOOTSTRAP_SOURCE}"
  exit 1
fi

cp -f "${bootstrap_source}" "${MATRIX_AUTH_NGINX_CONF}"

nginx -t
systemctl reload nginx

#@step "Install Certbot for Let's Encrypt"
apt-get update -y
apt-get install -y certbot
certbot --version

#@step "Enable and start certbot.timer for automatic renewal"
systemctl enable --now certbot.timer
systemctl status certbot.timer --no-pager

#@step "Issue/Renew Let's Encrypt certificate for matrix-auth.aiemotion.net"
certbot certonly --webroot \
  -w "${CERTBOT_WEBROOT}" \
  --non-interactive \
  --agree-tos \
  --email "${LETSENCRYPT_EMAIL}" \
  --keep-until-expiring \
  -d "${MATRIX_AUTH_DOMAIN}"

if [ ! -s "/etc/letsencrypt/live/${MATRIX_AUTH_DOMAIN}/fullchain.pem" ] || [ ! -s "/etc/letsencrypt/live/${MATRIX_AUTH_DOMAIN}/privkey.pem" ]; then
  echo "Let's Encrypt certificate files not found for ${MATRIX_AUTH_DOMAIN}."
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

#@step "Install TLS Nginx config"
tls_source="$(resolve_conf_source "${MATRIX_AUTH_NGINX_TLS_SOURCE}")"
if [ -z "${tls_source}" ]; then
  echo "TLS Nginx config not found: ${MATRIX_AUTH_NGINX_TLS_SOURCE}"
  exit 1
fi

cp -f "${tls_source}" "${MATRIX_AUTH_NGINX_CONF}"

nginx -t
systemctl reload nginx

#@step "Verify automatic renewal with certbot dry-run"
certbot renew --dry-run

#@group "Domain verification"

#@step "Verify matrix-auth.aiemotion.net DNS resolution"
#@env MATRIX_AUTH_DOMAIN=matrix-auth.aiemotion.net
#@env MATRIX_AUTH_TARGET_DOMAIN=root.aiemotion.net
domain="${MATRIX_AUTH_DOMAIN}"
expected_target="${MATRIX_AUTH_TARGET_DOMAIN%.}"

resolved_cname="$(dig +short "${domain}" CNAME | sed -n '$p' | sed 's/\.$//')"
if [ -n "${resolved_cname}" ]; then
  echo "Resolved CNAME: ${resolved_cname}"
  if [ "${resolved_cname}" != "${expected_target}" ]; then
    log_error "Unexpected CNAME target. Expected ${expected_target}, got ${resolved_cname}"
    exit 1
  fi
  log_ok "CNAME target matches expected value"
else
  echo "No CNAME returned for ${domain}; checking A/AAAA records instead."
  dig +short "${domain}" A
  dig +short "${domain}" AAAA
fi

#@step "Verify OIDC discovery endpoint and issuer"
#@env MATRIX_AUTH_DOMAIN=matrix-auth.aiemotion.net
domain="${MATRIX_AUTH_DOMAIN}"
discovery_url="https://${domain}/.well-known/openid-configuration"
expected_issuer="https://${domain}"

response="$(curl -fsS --max-time 20 "${discovery_url}")"
issuer="$(printf '%s' "${response}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("issuer",""))')"

if [ -z "${issuer}" ]; then
  log_error "No issuer field found in discovery response from ${discovery_url}"
  exit 1
fi

if [ "${issuer}" != "${expected_issuer}" ]; then
  log_error "Issuer mismatch. Expected ${expected_issuer}, got ${issuer}"
  exit 1
fi

log_ok "OIDC issuer verified: ${issuer}"
echo "Discovery URL: ${discovery_url}"

#@step "Show TLS certificate summary for matrix-auth.aiemotion.net"
#@env MATRIX_AUTH_DOMAIN=matrix-auth.aiemotion.net
domain="${MATRIX_AUTH_DOMAIN}"
echo | openssl s_client -connect "${domain}:443" -servername "${domain}" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
