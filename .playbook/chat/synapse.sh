#@ssh host=root.aiemotion.net

#@group "Synapse static secret files"

#@step "Generate registration shared secret"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
#@env SYNAPSE_REGISTRATION_SECRET_FILENAME=synapse-registration-secret.txt
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
target="${keys_dir}/${SYNAPSE_REGISTRATION_SECRET_FILENAME}"
mkdir -p "${keys_dir}"

if [ -s "${target}" ]; then
  echo "Secret already exists: ${target}"
  exit 0
fi
umask 027
openssl rand -hex 32 >"${target}"
chmod 640 "${target}"
echo "Generated secret: ${target}"

#@step "Generate macaroon secret key"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
#@env SYNAPSE_MACAROON_SECRET_FILENAME=synapse-macaroon-secret.txt
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
target="${keys_dir}/${SYNAPSE_MACAROON_SECRET_FILENAME}"
mkdir -p "${keys_dir}"

if [ -s "${target}" ]; then
  echo "Secret already exists: ${target}"
  exit 0
fi
umask 027
openssl rand -hex 32 >"${target}"
chmod 640 "${target}"
echo "Generated secret: ${target}"

#@step "Generate form secret"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
#@env SYNAPSE_FORM_SECRET_FILENAME=synapse-form-secret.txt
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
target="${keys_dir}/${SYNAPSE_FORM_SECRET_FILENAME}"
mkdir -p "${keys_dir}"

if [ -s "${target}" ]; then
  echo "Secret already exists: ${target}"
  exit 0
fi
umask 027
openssl rand -hex 32 >"${target}"
chmod 640 "${target}"
echo "Generated secret: ${target}"

#@step "Generate MAS secret"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
#@env SYNAPSE_MAS_SECRET_FILENAME=synapse-mas-secret.txt
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
target="${keys_dir}/${SYNAPSE_MAS_SECRET_FILENAME}"
mkdir -p "${keys_dir}"

if [ -s "${target}" ]; then
  echo "Secret already exists: ${target}"
  exit 0
fi
umask 027
openssl rand -hex 32 >"${target}"
chmod 640 "${target}"
echo "Generated secret: ${target}"

#@step "Generate all static secrets"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
set -euo pipefail

keys_dir="${SYNAPSE_KEYS_DIR}"
mkdir -p "${keys_dir}"

generate_if_missing() {
  target="$1"
  if [ -s "${target}" ]; then
    echo "Secret already exists: ${target}"
    return 0
  fi
  umask 027
  openssl rand -hex 32 >"${target}"
  chmod 640 "${target}"
  echo "Generated secret: ${target}"
}

generate_if_missing "${keys_dir}/synapse-registration-secret.txt"
generate_if_missing "${keys_dir}/synapse-macaroon-secret.txt"
generate_if_missing "${keys_dir}/synapse-form-secret.txt"
generate_if_missing "${keys_dir}/synapse-mas-secret.txt"

#@group "Synapse signing key"

#@step "Generate Synapse signing key"
#@env SYNAPSE_KEYS_DIR=/etc/chat/synapse/keys
#@env SYNAPSE_SIGNING_KEY_FILENAME=synapse-signing.key
#@env SYNAPSE_CONTAINER=synapse
#@env SYNAPSE_IMAGE=matrixdotorg/synapse:latest
keys_dir="${SYNAPSE_KEYS_DIR}"
signing_key_filename="${SYNAPSE_SIGNING_KEY_FILENAME}"
container_name="${SYNAPSE_CONTAINER-}"
synapse_image="${SYNAPSE_IMAGE}"

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

mkdir -p "${keys_dir}"
new_key_file="${tmpdir}/new_signing.key"

echo "Generating new Synapse signing key from container: ${container_name}"
if docker exec "${container_name}" python3 -m synapse._scripts.generate_signing_key -o /tmp/new_signing.key 2>/dev/null; then
  docker cp "${container_name}:/tmp/new_signing.key" "${new_key_file}"
  docker exec "${container_name}" rm -f /tmp/new_signing.key >/dev/null 2>&1 || true
else
  echo "Container exec failed. Falling back to image: ${synapse_image}" >&2
  docker run --rm --entrypoint python3 "${synapse_image}" -m synapse._scripts.generate_signing_key -o - >"${new_key_file}"
fi

if [ ! -s "${new_key_file}" ]; then
  echo "Failed to generate signing key." >&2
  exit 1
fi

key_id="$(awk 'NR==1 {print $2}' "${new_key_file}")"
if [ -z "${key_id}" ]; then
  echo "Could not extract key ID from generated key." >&2
  exit 1
fi

new_key_host_path="${keys_dir}/${signing_key_filename}"
new_key_config_path="/data/keys/${signing_key_filename}"

if [ -f "${new_key_host_path}" ]; then
  old_key_backup="${keys_dir}/old_${signing_key_filename}.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -a "${new_key_host_path}" "${old_key_backup}"
  echo "Backed up old signing key: ${old_key_backup}"
fi

cp -a "${new_key_file}" "${new_key_host_path}"
chmod 640 "${new_key_host_path}"
echo "Wrote new signing key: ${new_key_host_path}"
echo "New signing key path: ${new_key_config_path}"
echo "Generated key id: ${key_id}"

#@group "Synapse storage provider"

#@step "Install Synapse S3 storage provider in running container"
#@env SYNAPSE_CONTAINER=synapse
#@env SYNAPSE_S3_PROVIDER_PATH=/opt/synapse-s3-storage-provider
container_name="${SYNAPSE_CONTAINER}"
provider_path="${SYNAPSE_S3_PROVIDER_PATH}"

if ! docker ps --format '{{.Names}}' | grep -Fxq "${container_name}"; then
  echo "Container '${container_name}' is not running. Start Synapse first."
  exit 1
fi

docker exec "${container_name}" python3 -m pip install "${provider_path}"
echo "Installed Synapse S3 storage provider from ${provider_path} in ${container_name}"

#@group "Route53 DNS for aiemotion.net"

#@step "Register aiemotion.net A record"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env ROUTE53_TTL=300
#@env SYNAPSE_BASE_DOMAIN=aiemotion.net
#@env SYNAPSE_BASE_IPV4=157.180.4.111
. ".playbook/lib/chat.sh"
init_aws_cmd

domain="${SYNAPSE_BASE_DOMAIN}"
domain_ipv4="${SYNAPSE_BASE_IPV4}"
route53_zone_id="${ROUTE53_HOSTED_ZONE_ID}"
route53_ttl="${ROUTE53_TTL}"

tmp_change_batch="$(mktemp)"
cleanup() {
  rm -f "${tmp_change_batch}"
}
trap cleanup EXIT

cat >"${tmp_change_batch}" <<EOF
{
  "Comment": "UPSERT A ${domain} -> ${domain_ipv4}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${domain%.}.",
        "Type": "A",
        "TTL": ${route53_ttl},
        "ResourceRecords": [{ "Value": "${domain_ipv4}" }]
      }
    }
  ]
}
EOF

if ! "${CHAT_AWS_CMD[@]}" route53 change-resource-record-sets \
  --hosted-zone-id "${route53_zone_id}" \
  --change-batch "file://${tmp_change_batch}" >/dev/null; then
  log_error "Failed to register A record ${domain} -> ${domain_ipv4}"
  exit 1
fi

log_ok "Route53 record registered: ${domain} -> ${domain_ipv4}"

#@step "Verify aiemotion.net DNS resolution"
#@env SYNAPSE_BASE_DOMAIN=aiemotion.net
#@env SYNAPSE_BASE_IPV4=157.180.4.111
domain="${SYNAPSE_BASE_DOMAIN}"
expected_ipv4="${SYNAPSE_BASE_IPV4}"

resolved_a="$(dig +short "${domain}" A | tr -d '\r')"
echo "Resolved A records:"
printf '%s\n' "${resolved_a}"

if ! printf '%s\n' "${resolved_a}" | grep -Fx -- "${expected_ipv4}" >/dev/null 2>&1; then
  echo "A record mismatch for ${domain}. Expected to include ${expected_ipv4}" >&2
  exit 1
fi

echo "A record contains expected value: ${expected_ipv4}"

#@group "Nginx + Let's Encrypt for aiemotion.net"

#@env SYNAPSE_BASE_DOMAIN=aiemotion.net
#@env SYNAPSE_BASE_NGINX_CONF=/etc/nginx/conf.d/aiemotion.net.conf
#@env SYNAPSE_BASE_NGINX_BOOTSTRAP_SOURCE=nginx/bootstrap/aiemotion.net.conf
#@env SYNAPSE_BASE_NGINX_TLS_SOURCE=nginx/conf.d/aiemotion.net.conf
#@env LETSENCRYPT_EMAIL=admin@aiemotion.net
#@env CERTBOT_WEBROOT=/var/www/letsencrypt

#@step "Ensure Nginx is installed and running"
apt-get update -y
apt-get install -y nginx
systemctl enable --now nginx
systemctl status nginx --no-pager

#@step "Install bootstrap Nginx config for ACME and Matrix discovery"
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
bootstrap_source="$(resolve_conf_source "${SYNAPSE_BASE_NGINX_BOOTSTRAP_SOURCE}")"
if [ -z "${bootstrap_source}" ]; then
  echo "Bootstrap Nginx config not found: ${SYNAPSE_BASE_NGINX_BOOTSTRAP_SOURCE}"
  exit 1
fi

cp -f "${bootstrap_source}" "${SYNAPSE_BASE_NGINX_CONF}"

nginx -t
systemctl reload nginx

#@step "Install Certbot for Let's Encrypt"
apt-get update -y
apt-get install -y certbot
certbot --version

#@step "Issue/Renew Let's Encrypt certificate for aiemotion.net"
certbot certonly --webroot \
  -w "${CERTBOT_WEBROOT}" \
  --non-interactive \
  --agree-tos \
  --email "${LETSENCRYPT_EMAIL}" \
  --keep-until-expiring \
  -d "${SYNAPSE_BASE_DOMAIN}"

if [ ! -s "/etc/letsencrypt/live/${SYNAPSE_BASE_DOMAIN}/fullchain.pem" ] || [ ! -s "/etc/letsencrypt/live/${SYNAPSE_BASE_DOMAIN}/privkey.pem" ]; then
  echo "Let's Encrypt certificate files not found for ${SYNAPSE_BASE_DOMAIN}."
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

#@step "Install TLS Nginx config for aiemotion.net"
tls_source="$(resolve_conf_source "${SYNAPSE_BASE_NGINX_TLS_SOURCE}")"
if [ -z "${tls_source}" ]; then
  echo "TLS Nginx config not found: ${SYNAPSE_BASE_NGINX_TLS_SOURCE}"
  exit 1
fi

cp -f "${tls_source}" "${SYNAPSE_BASE_NGINX_CONF}"

nginx -t
systemctl reload nginx
