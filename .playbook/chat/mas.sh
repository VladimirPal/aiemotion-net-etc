#@ssh host=root.aiemotion.net

#@group "MAS Dockerfile patch"

#@step "Apply MAS Dockerfile resource patch"
#@env MAS_REPO_DIR=/etc/chat/mas/repo
#@env MAS_DOCKERFILE_PATCH=/etc/chat/mas/patches/patch-dockerfile.patch
. ".playbook/lib/base.sh"

need git || exit 1

mas_repo_dir="${MAS_REPO_DIR}"
mas_patch_path="${MAS_DOCKERFILE_PATCH}"

mas_repo_dir="${mas_repo_dir#./}"
mas_patch_path="${mas_patch_path#./}"

if [ -d "${MAS_REPO_DIR}" ]; then
  mas_repo_dir="${MAS_REPO_DIR}"
elif [ -d "/etc/control/${mas_repo_dir}" ]; then
  mas_repo_dir="/etc/control/${mas_repo_dir}"
fi

if [ -f "${MAS_DOCKERFILE_PATCH}" ]; then
  mas_patch_path="${MAS_DOCKERFILE_PATCH}"
elif [ -f "/etc/control/${mas_patch_path}" ]; then
  mas_patch_path="/etc/control/${mas_patch_path}"
fi

if [ ! -d "${mas_repo_dir}" ]; then
  echo "MAS repo directory not found: ${MAS_REPO_DIR}" >&2
  exit 1
fi

if [ ! -f "${mas_patch_path}" ]; then
  echo "MAS patch file not found: ${MAS_DOCKERFILE_PATCH}" >&2
  exit 1
fi

if git -C "${mas_repo_dir}" apply --reverse --check "${mas_patch_path}" >/dev/null 2>&1; then
  echo "MAS Dockerfile patch already applied: ${mas_patch_path}"
else
  git -C "${mas_repo_dir}" apply "${mas_patch_path}"
  echo "Applied MAS Dockerfile patch: ${mas_patch_path}"
fi

#@group "MAS keys"

#@step "Generate MAS SSH RSA keys and authorized_keys"
#@env MAS_SSH_DIR=/etc/chat/mas/ssh
#@env MAS_SSH_PRIVATE_KEY_FILENAME=id_rsa
#@env MAS_SSH_PUBLIC_KEY_FILENAME=id_rsa.pub
#@env MAS_AUTHORIZED_KEYS_FILENAME=authorized_keys
#@env MAS_SSH_KEY_COMMENT=mas-local-access
. ".playbook/lib/mas.sh"

mas_generate_ssh_keys_and_authorized_keys \
  "${MAS_SSH_DIR}" \
  "${MAS_SSH_PRIVATE_KEY_FILENAME}" \
  "${MAS_SSH_PUBLIC_KEY_FILENAME}" \
  "${MAS_AUTHORIZED_KEYS_FILENAME}" \
  "${MAS_SSH_KEY_COMMENT}"

#@step "Generate MAS encryption secret"
#@env MAS_KEYS_DIR=/etc/chat/mas/keys
#@env MAS_ENCRYPTION_SECRET_FILENAME=mas-encryption.hex
. ".playbook/lib/mas.sh"

mas_generate_secret_if_missing "${MAS_KEYS_DIR}" "${MAS_ENCRYPTION_SECRET_FILENAME}"

#@step "Generate MAS OIDC signing keys"
#@env MAS_KEYS_DIR=/etc/chat/mas/keys
#@env MAS_CONFIG_PATH=/etc/chat/mas/config.yaml
#@env MAS_IMAGE=ghcr.io/element-hq/matrix-authentication-service:latest
. ".playbook/lib/mas.sh"

mas_generate_oidc_signing_keys "${MAS_KEYS_DIR}" "${MAS_CONFIG_PATH}" "${MAS_IMAGE}"

#@group "Route53 DNS for matrix-auth.aiemotion.net"

#@step "Register matrix-auth.aiemotion.net A record"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env ROUTE53_TTL=300
#@env MATRIX_AUTH_DOMAIN=matrix-auth.aiemotion.net
#@env MATRIX_AUTH_IPV4=157.180.4.111
. ".playbook/lib/chat.sh"
init_aws_cmd

matrix_auth_domain="${MATRIX_AUTH_DOMAIN}"
matrix_auth_ipv4="${MATRIX_AUTH_IPV4}"
route53_zone_id="${ROUTE53_HOSTED_ZONE_ID}"
route53_ttl="${ROUTE53_TTL}"

tmp_change_batch="$(mktemp)"
cleanup() {
  rm -f "${tmp_change_batch}"
}
trap cleanup EXIT

cat >"${tmp_change_batch}" <<EOF
{
  "Comment": "UPSERT A ${matrix_auth_domain} -> ${matrix_auth_ipv4}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${matrix_auth_domain%.}.",
        "Type": "A",
        "TTL": ${route53_ttl},
        "ResourceRecords": [{ "Value": "${matrix_auth_ipv4}" }]
      }
    }
  ]
}
EOF

if ! "${CHAT_AWS_CMD[@]}" route53 change-resource-record-sets \
  --hosted-zone-id "${route53_zone_id}" \
  --change-batch "file://${tmp_change_batch}" >/dev/null; then
  log_error "Failed to register A record ${matrix_auth_domain} -> ${matrix_auth_ipv4}"
  exit 1
fi

log_ok "Route53 record registered: ${matrix_auth_domain} -> ${matrix_auth_ipv4}"

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

#@step "Enable and start certbot.timer for automatic renewal"
systemctl enable --now certbot.timer
systemctl status certbot.timer --no-pager

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
#@env MATRIX_AUTH_IPV4=157.180.4.111
domain="${MATRIX_AUTH_DOMAIN}"
expected_ipv4="${MATRIX_AUTH_IPV4}"

resolved_a="$(dig +short "${domain}" A | tr -d '\r')"
echo "Resolved A records:"
printf '%s\n' "${resolved_a}"

if ! printf '%s\n' "${resolved_a}" | grep -Fx -- "${expected_ipv4}" >/dev/null 2>&1; then
  echo "A record mismatch for ${domain}. Expected to include ${expected_ipv4}" >&2
  exit 1
fi

echo "A record contains expected value: ${expected_ipv4}"

#@step "Verify OIDC discovery endpoint and issuer"
#@env MATRIX_AUTH_DOMAIN=matrix-auth.aiemotion.net
domain="${MATRIX_AUTH_DOMAIN}"
discovery_url="https://${domain}/.well-known/openid-configuration"
expected_issuer="https://${domain}"

response="$(curl -fsS --max-time 20 "${discovery_url}")"
issuer="$(printf '%s' "${response}" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("issuer",""))')"

if [ -z "${issuer}" ]; then
  echo "No issuer field found in discovery response from ${discovery_url}" >&2
  exit 1
fi

if [ "${issuer}" != "${expected_issuer}" ]; then
  echo "Issuer mismatch. Expected ${expected_issuer}, got ${issuer}" >&2
  exit 1
fi

echo "OIDC issuer verified: ${issuer}"
echo "Discovery URL: ${discovery_url}"

#@step "Show TLS certificate summary for matrix-auth.aiemotion.net"
#@env MATRIX_AUTH_DOMAIN=matrix-auth.aiemotion.net
domain="${MATRIX_AUTH_DOMAIN}"
echo | openssl s_client -connect "${domain}:443" -servername "${domain}" 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
