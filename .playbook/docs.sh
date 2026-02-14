#@ssh host=root.aiemotion.net

#@group "Install"

#@step "Generate dedicated SSH key for memory-alive-docs submodule"
#@env DOCS_DEPLOY_KEY_PATH=/root/.ssh/memory_alive_docs_rsa
#@env DOCS_DEPLOY_KEY_COMMENT=memory-alive-docs-deploy
mkdir -p /root/.ssh
chmod 700 /root/.ssh

if [ ! -f "${DOCS_DEPLOY_KEY_PATH}" ]; then
  ssh-keygen -t rsa -b 4096 -C "${DOCS_DEPLOY_KEY_COMMENT}" -N "" -f "${DOCS_DEPLOY_KEY_PATH}"
  echo "Created SSH key: ${DOCS_DEPLOY_KEY_PATH}"
else
  echo "SSH key already exists: ${DOCS_DEPLOY_KEY_PATH}"
fi

chmod 600 "${DOCS_DEPLOY_KEY_PATH}"
chmod 644 "${DOCS_DEPLOY_KEY_PATH}.pub"

#@step "Print public key to add as GitHub deploy key (read-only)"
#@env DOCS_DEPLOY_KEY_PATH=/root/.ssh/memory_alive_docs_rsa
echo "Add this public key to GitHub repo VladimirPal/memory-alive-docs as a deploy key:"
cat "${DOCS_DEPLOY_KEY_PATH}.pub"

#@step "Ensure GitHub host key is present in known_hosts"
if [ ! -f /root/.ssh/known_hosts ] || ! ssh-keygen -F github.com -f /root/.ssh/known_hosts >/dev/null 2>&1; then
  ssh-keyscan -H github.com >>/root/.ssh/known_hosts
  echo "Added github.com host key to /root/.ssh/known_hosts"
else
  echo "github.com host key already present in /root/.ssh/known_hosts"
fi
chmod 644 /root/.ssh/known_hosts

#@step "Ensure dedicated SSH host alias for memory-alive-docs exists"
#@env DOCS_SUBMODULES_SSH_CONFIG=/etc/ssh/submodules_config
#@env DOCS_SSH_HOST_ALIAS=github-memory-alive-docs
#@env DOCS_DEPLOY_KEY_PATH=/root/.ssh/memory_alive_docs_rsa
mkdir -p /etc/ssh
touch "${DOCS_SUBMODULES_SSH_CONFIG}"

if grep -Fxq "Host ${DOCS_SSH_HOST_ALIAS}" "${DOCS_SUBMODULES_SSH_CONFIG}"; then
  echo "Host alias ${DOCS_SSH_HOST_ALIAS} already exists in ${DOCS_SUBMODULES_SSH_CONFIG}"
else
  cat >>"${DOCS_SUBMODULES_SSH_CONFIG}" <<EOF
Host ${DOCS_SSH_HOST_ALIAS}
    HostName github.com
    User git
    IdentityFile ${DOCS_DEPLOY_KEY_PATH}
    IdentitiesOnly yes
EOF
  echo "Added host alias ${DOCS_SSH_HOST_ALIAS} to ${DOCS_SUBMODULES_SSH_CONFIG}"
fi

chmod 600 "${DOCS_SUBMODULES_SSH_CONFIG}"

#@step "Add memory-alive-docs repo as etckeeper submodule in /etc/control/docs/memory-alive-docs"
#@env DOCS_REPO_URL=git@github-memory-alive-docs:VladimirPal/memory-alive-docs.git
#@env DOCS_SUBMODULE_PATH=control/docs/memory-alive-docs
#@env DOCS_GITIGNORE_LINE_1=!control/docs/
#@env DOCS_GITIGNORE_LINE_2=!control/docs/**
#@env DOCS_GITIGNORE_LINE_3=!control/docs/memory-alive-docs/
#@env DOCS_GITIGNORE_LINE_4=!control/docs/memory-alive-docs/**
if ! grep -Fxq "$DOCS_GITIGNORE_LINE_1" /etc/.gitignore; then
  echo "$DOCS_GITIGNORE_LINE_1" >>/etc/.gitignore
fi
if ! grep -Fxq "$DOCS_GITIGNORE_LINE_2" /etc/.gitignore; then
  echo "$DOCS_GITIGNORE_LINE_2" >>/etc/.gitignore
fi
if ! grep -Fxq "$DOCS_GITIGNORE_LINE_3" /etc/.gitignore; then
  echo "$DOCS_GITIGNORE_LINE_3" >>/etc/.gitignore
fi
if ! grep -Fxq "$DOCS_GITIGNORE_LINE_4" /etc/.gitignore; then
  echo "$DOCS_GITIGNORE_LINE_4" >>/etc/.gitignore
fi

mkdir -p /etc/control/docs

if git -C /etc config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | grep -q " ${DOCS_SUBMODULE_PATH}$"; then
  echo "Submodule path ${DOCS_SUBMODULE_PATH} already configured in /etc/.gitmodules."
elif [ -d "/etc/${DOCS_SUBMODULE_PATH}/.git" ] || [ -f "/etc/${DOCS_SUBMODULE_PATH}/.git" ]; then
  echo "Existing git repo detected at /etc/${DOCS_SUBMODULE_PATH}; skipping submodule add."
else
  git -C /etc submodule add "${DOCS_REPO_URL}" "${DOCS_SUBMODULE_PATH}"
  echo "Added submodule ${DOCS_REPO_URL} at /etc/${DOCS_SUBMODULE_PATH}"
fi

git -C /etc add .gitignore .gitmodules ssh/submodules_config control/docs/memory-alive-docs

if ! git -C /etc diff --cached --quiet; then
  git -C /etc commit -m "Add memory-alive-docs submodule"
else
  echo "No changes staged in /etc; nothing to commit or push."
fi

#@group Docusaurus

#@step "Status of docusaurus-builder service"
scs status docusaurus-builder

#@step "Start docusaurus-builder service"
scs start docusaurus-builder

#@step "Build docusaurus-builder service"
scs build docusaurus-builder

#@step "View docusaurus-builder service logs"
scs logs docusaurus-builder

#@step "Check for updates for docusaurus-builder"
scs check-update docusaurus-builder

#@step "Upgrade docusaurus-builder to the latest version"
scs upgrade docusaurus-builder

#@step "Prepare Docusaurus directory"
/etc/docusaurus/prepare-dir.sh

#@step "Apply Route53 A record for docs.aiemotion.net"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env ROUTE53_TTL=300
#@env DOCS_DOMAIN=docs.aiemotion.net
#@env DOCS_IPV4=157.180.4.111
. ".playbook/lib/mailserver.sh"
init_aws_cmd

add_a_record "${ROUTE53_HOSTED_ZONE_ID}" "${DOCS_DOMAIN}" "${DOCS_IPV4}" || exit 1

#@step "Verify docs.aiemotion.net DNS A record"
#@env DOCS_DOMAIN=docs.aiemotion.net
#@env DOCS_IPV4=157.180.4.111
. ".playbook/lib/mailserver.sh"

verify_dns_contains "A" "${DOCS_DOMAIN%.}" "${DOCS_IPV4}" || exit 1

#@group "Nginx + Let's Encrypt for Docusaurus"
#@env DOCS_TLS_DOMAIN=docs.aiemotion.net
#@env LETSENCRYPT_EMAIL=admin@aiemotion.net
#@env CERTBOT_WEBROOT=/var/www/letsencrypt
#@env DOCS_NGINX_CONF=/etc/nginx/conf.d/docs.aiemotion.net.conf

#@step "Install Certbot for Let's Encrypt"
apt-get update -y
apt-get install -y certbot
certbot --version

#@step "Enable and start certbot.timer for automatic renewal"
systemctl enable --now certbot.timer
systemctl status certbot.timer --no-pager

#@step "Issue/Renew Let's Encrypt certificate for docs.aiemotion.net"
certbot certonly --webroot \
  -w "${CERTBOT_WEBROOT}" \
  --non-interactive \
  --agree-tos \
  --email "${LETSENCRYPT_EMAIL}" \
  --keep-until-expiring \
  -d "${DOCS_TLS_DOMAIN}"

if [ ! -s "/etc/letsencrypt/live/${DOCS_TLS_DOMAIN}/fullchain.pem" ] || [ ! -s "/etc/letsencrypt/live/${DOCS_TLS_DOMAIN}/privkey.pem" ]; then
  echo "Let's Encrypt certificate files not found for ${DOCS_TLS_DOMAIN}."
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
