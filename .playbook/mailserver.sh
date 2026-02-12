#@ssh host=root.aiemotion.net

#@group "Manage mailserver"
#@step "Show running mailserver docker container"
docker ps --filter "name=mailserver"

#@step "View mailserver docker container logs"
docker logs --tail 200 mailserver

#@step "Status of mailserver service"
scs status mailserver

#@step "View mailserver service logs"
scs logs mailserver

#@step "Restart mailserver service"
scs restart mailserver

#@step "Stop mailserver service"
scs stop mailserver

#@step "Start mailserver service"
scs start mailserver

#@step "Build mailserver docker image"
scs build mailserver

#@step "Check for updates for mailserver"
scs check-update mailserver

#@step "Upgrade mailserver to the latest version"
scs upgrade mailserver

#@step "Backup mailserver"
scs backup mailserver

#@group "Mailserver maintenance"
#@step "Clean old rotated mail logs in container"
docker exec mailserver find /var/log/mail -name "*.log.*" -mtime +30 -delete

#@step "Create admin mailbox account (if needed)"
#@env MAIL_ADMIN_ACCOUNT=admin@aiemotion.net
#@env MAIL_ADMIN_PASSWORD=
docker exec mailserver setup email add "${MAIL_ADMIN_ACCOUNT}" "${MAIL_ADMIN_PASSWORD}"

#@group "Mailbox onboarding"
#@step "Create person mailboxes"
#@env DMS_CONTAINER_NAME=mailserver
#@env MAIL_DOMAIN=aiemotion.net
#@env MAIL_PASSWORD_MRV=
#@env MAIL_PASSWORD_AKHAT=
#@env MAIL_PASSWORD_NORDIN=
. ".playbook/lib/mailserver.sh"

mailserver_create_team_mailboxes \
  "${DMS_CONTAINER_NAME}" \
  "${MAIL_DOMAIN}" \
  "${MAIL_PASSWORD_MRV}" \
  "${MAIL_PASSWORD_AKHAT}" \
  "${MAIL_PASSWORD_NORDIN}"

#@step "Create operator/admin/meta/hello/support/billing mailboxes with passwords"
#@env DMS_CONTAINER_NAME=mailserver
#@env MAIL_DOMAIN=aiemotion.net
#@env MAIL_PASSWORD_OPERATOR=
#@env MAIL_PASSWORD_ADMIN=
#@env MAIL_PASSWORD_META=
#@env MAIL_PASSWORD_HELLO=
#@env MAIL_PASSWORD_SUPPORT=
#@env MAIL_PASSWORD_BILLING=
echo "Creating shared and inbound mailboxes for ${MAIL_DOMAIN}..."
docker exec "${DMS_CONTAINER_NAME}" setup email add "operator@${MAIL_DOMAIN}" "${MAIL_PASSWORD_OPERATOR}"
echo "Mailbox ensured: operator@${MAIL_DOMAIN}"
docker exec "${DMS_CONTAINER_NAME}" setup email add "admin@${MAIL_DOMAIN}" "${MAIL_PASSWORD_ADMIN}"
echo "Mailbox ensured: admin@${MAIL_DOMAIN}"
docker exec "${DMS_CONTAINER_NAME}" setup email add "meta@${MAIL_DOMAIN}" "${MAIL_PASSWORD_META}"
echo "Mailbox ensured: meta@${MAIL_DOMAIN}"
docker exec "${DMS_CONTAINER_NAME}" setup email add "hello@${MAIL_DOMAIN}" "${MAIL_PASSWORD_HELLO}"
echo "Mailbox ensured: hello@${MAIL_DOMAIN}"
docker exec "${DMS_CONTAINER_NAME}" setup email add "support@${MAIL_DOMAIN}" "${MAIL_PASSWORD_SUPPORT}"
echo "Mailbox ensured: support@${MAIL_DOMAIN}"
docker exec "${DMS_CONTAINER_NAME}" setup email add "billing@${MAIL_DOMAIN}" "${MAIL_PASSWORD_BILLING}"
echo "Mailbox ensured: billing@${MAIL_DOMAIN}"
echo "Mailbox creation completed: operator, admin, meta, hello, support, billing"

#@step "Configure mailbox-level forwarding hello/support to operator"
#@env DMS_CONTAINER_NAME=mailserver
#@env MAIL_DOMAIN=aiemotion.net
#@env DMS_CONFIG_DIR=/tmp/docker-mailserver
. ".playbook/lib/mailserver.sh"

mailserver_configure_operator_mailbox_forwarding "${DMS_CONTAINER_NAME}" "${MAIL_DOMAIN}" "${DMS_CONFIG_DIR}"
scs restart mailserver

#@step "Configure mailbox-level forwarding billing/meta to admin"
#@env DMS_CONTAINER_NAME=mailserver
#@env MAIL_DOMAIN=aiemotion.net
#@env DMS_CONFIG_DIR=/tmp/docker-mailserver
. ".playbook/lib/mailserver.sh"

mailserver_configure_admin_mailbox_forwarding "${DMS_CONTAINER_NAME}" "${MAIL_DOMAIN}" "${DMS_CONFIG_DIR}"
scs restart mailserver

#@group "Install"

#@step "Install AWS CLI"
apt-get update -y
apt-get install -y awscli

aws --version

#@step "Add mailserver repo as etckeeper submodule in /etc/mailserver/repo"
#@env MAILSERVER_REPO_URL=git@github.com:docker-mailserver/docker-mailserver.git
#@env MAILSERVER_SUBMODULE_PATH=mailserver/repo
#@env MAILSERVER_GITIGNORE_LINE_1=!mailserver/
#@env MAILSERVER_GITIGNORE_LINE_2=!mailserver/**
#@env MAILSERVER_GITIGNORE_LINE_3=mailserver/backups
#@env MAILSERVER_GITIGNORE_LINE_4=mailserver/docker-data
if ! grep -Fxq "$MAILSERVER_GITIGNORE_LINE_1" /etc/.gitignore; then
  echo "$MAILSERVER_GITIGNORE_LINE_1" >>/etc/.gitignore
fi
if ! grep -Fxq "$MAILSERVER_GITIGNORE_LINE_2" /etc/.gitignore; then
  echo "$MAILSERVER_GITIGNORE_LINE_2" >>/etc/.gitignore
fi
if ! grep -Fxq "$MAILSERVER_GITIGNORE_LINE_3" /etc/.gitignore; then
  echo "$MAILSERVER_GITIGNORE_LINE_3" >>/etc/.gitignore
fi
if ! grep -Fxq "$MAILSERVER_GITIGNORE_LINE_4" /etc/.gitignore; then
  echo "$MAILSERVER_GITIGNORE_LINE_4" >>/etc/.gitignore
fi

mkdir -p /etc/mailserver

if git -C /etc config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | grep -q " ${MAILSERVER_SUBMODULE_PATH}$"; then
  echo "Submodule path ${MAILSERVER_SUBMODULE_PATH} already configured in /etc/.gitmodules."
  exit 0
elif [ -d "/etc/${MAILSERVER_SUBMODULE_PATH}/.git" ] || [ -f "/etc/${MAILSERVER_SUBMODULE_PATH}/.git" ]; then
  echo "Existing git repo detected at /etc/${MAILSERVER_SUBMODULE_PATH}; skipping submodule add."
  exit 0
else
  git -C /etc submodule add "$MAILSERVER_REPO_URL" "$MAILSERVER_SUBMODULE_PATH"
  echo "Added submodule ${MAILSERVER_REPO_URL} at /etc/${MAILSERVER_SUBMODULE_PATH}"
fi

git -C /etc add .gitignore .gitmodules mailserver

if ! git -C /etc diff --cached --quiet; then
  git -C /etc commit -m "Add mailserver repo submodule"
else
  echo "No changes staged in /etc; nothing to commit or push."
fi

#@step "Build mailserver image"
scs build mailserver

#@group "Route53 DNS"
#@env MAIL_DOMAIN=aiemotion.net
#@env MAILSERVER_FQDN=mail.aiemotion.net
#@env MAILSERVER_IPV4=157.180.4.111
#@env ROUTE53_MX_PRIORITY=10
#@env ROUTE53_SPF_VALUE=v="spf1 ip4:157.180.4.111 -all"
#@env ROUTE53_DMARC_NAME=_dmarc
#@env ROUTE53_DMARC_VALUE="v=DMARC1; p=quarantine; sp=quarantine; fo=0; adkim=r; aspf=r; pct=10; rf=afrf; ri=86400; rua=mailto:dmarc.report@aiemotion.net; ruf=mailto:dmarc.report@aiemotion.net"
#@env ROUTE53_DKIM_SELECTOR=mail
#@env DMS_CONTAINER_NAME=mailserver

#@step "Apply base mail DNS records in Route53 (A + MX + SPF + DMARC)"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env ROUTE53_TTL=300
. ".playbook/lib/mailserver.sh"
init_aws_cmd

add_a_record "${ROUTE53_HOSTED_ZONE_ID}" "${MAILSERVER_FQDN}" "${MAILSERVER_IPV4}" || exit 1
add_mx_record "${ROUTE53_HOSTED_ZONE_ID}" "${MAIL_DOMAIN}" "${ROUTE53_MX_PRIORITY}" "${MAILSERVER_FQDN}" || exit 1
add_spf_record "${ROUTE53_HOSTED_ZONE_ID}" "${MAIL_DOMAIN}" "${ROUTE53_SPF_VALUE}" || exit 1
add_dmarc_record "${ROUTE53_HOSTED_ZONE_ID}" "${MAIL_DOMAIN}" "${ROUTE53_DMARC_NAME}" "${ROUTE53_DMARC_VALUE}" || exit 1

show_hetzner_ptr_hint "${MAILSERVER_IPV4}" "${MAILSERVER_FQDN}"

#@step "Verify DNS records (A, MX, SPF, DMARC, DKIM)"
. ".playbook/lib/mailserver.sh"

verify_dns_contains "A" "${MAILSERVER_FQDN%.}" "${MAILSERVER_IPV4}" || exit 1
verify_dns_contains "MX" "${MAIL_DOMAIN%.}" "${ROUTE53_MX_PRIORITY} ${MAILSERVER_FQDN%.}." || exit 1
verify_dns_contains "TXT" "${MAIL_DOMAIN%.}" "${ROUTE53_SPF_VALUE}" || exit 1
verify_dns_contains "TXT" "${ROUTE53_DMARC_NAME%.}.${MAIL_DOMAIN%.}" "${ROUTE53_DMARC_VALUE}" || exit 1

ROUTE53_DKIM_PUBLIC_KEY="$(extract_dkim_public_key "${DMS_CONTAINER_NAME}" "${MAIL_DOMAIN}" "${ROUTE53_DKIM_SELECTOR}" || true)"
DKIM_KEY_PREFIX="$(printf '%s' "${ROUTE53_DKIM_PUBLIC_KEY}" | cut -c1-24)"
verify_dns_contains "TXT" "${ROUTE53_DKIM_SELECTOR%._domainkey}._domainkey.${MAIL_DOMAIN%.}" "v=DKIM1; h=sha256; k=rsa; p=${DKIM_KEY_PREFIX}" || exit 1

#@group "SSL/TLS"
#@env DMS_PROJECT_DIR=/etc/mailserver
#@env MAILSERVER_FQDN=mail.aiemotion.net
#@env MAIL_DOMAIN=aiemotion.net
#@env MAILSERVER_SMTP_SUBMISSION_PORT=587
#@env MAILSERVER_IMAP_STARTTLS_PORT=143
#@env MAILSERVER_POP3_STARTTLS_PORT=110
#@env LETSENCRYPT_EMAIL=admin@aiemotion.net
#@env CERTBOT_IMAGE=certbot/certbot:latest
#@env CERTBOT_LETSENCRYPT_DIR=/etc/letsencrypt
#@env CERTBOT_LOG_DIR=/var/log/letsencrypt
#@env TESTSSL_TMP_DIR=/tmp
#@env TESTSSL_IMAGE=drwetter/testssl.sh:latest
#@env TESTSSL_EXTRA_ARGS=--quiet

#@step "Issue/Renew Let's Encrypt certificate for mail FQDN"
mkdir -p "${CERTBOT_LETSENCRYPT_DIR}" "${CERTBOT_LOG_DIR}"

docker run --rm \
  -v "${CERTBOT_LETSENCRYPT_DIR}:/etc/letsencrypt" \
  -v "${CERTBOT_LOG_DIR}:/var/log/letsencrypt" \
  -p 80:80 \
  "${CERTBOT_IMAGE}" \
  certonly --standalone --non-interactive --agree-tos \
  --email "${LETSENCRYPT_EMAIL}" \
  --keep-until-expiring \
  -d "${MAILSERVER_FQDN}"

LETSENCRYPT_LIVE_DIR="${CERTBOT_LETSENCRYPT_DIR}/live/${MAILSERVER_FQDN}"
if [ ! -s "${LETSENCRYPT_LIVE_DIR}/fullchain.pem" ] || [ ! -s "${LETSENCRYPT_LIVE_DIR}/privkey.pem" ]; then
  echo "Let's Encrypt certificate files not found for ${MAILSERVER_FQDN} in ${LETSENCRYPT_LIVE_DIR}."
  exit 1
fi

#@step "Test SSL/TLS with testssl.sh (HTTPS + STARTTLS)"
docker run --rm "${TESTSSL_IMAGE}" --quiet --header "https://${MAILSERVER_FQDN}"
docker run --rm "${TESTSSL_IMAGE}" --quiet --starttls smtp "${MAILSERVER_FQDN}:${MAILSERVER_SMTP_SUBMISSION_PORT}"
docker run --rm "${TESTSSL_IMAGE}" --quiet --starttls imap "${MAILSERVER_FQDN}:${MAILSERVER_IMAP_STARTTLS_PORT}"
docker run --rm "${TESTSSL_IMAGE}" --quiet --starttls pop3 "${MAILSERVER_FQDN}:${MAILSERVER_POP3_STARTTLS_PORT}"

#@step "Start mailserver container for key generation"
#@env DMS_PROJECT_DIR=/etc/mailserver
#@env DMS_CONTAINER_NAME=mailserver
if ! docker compose -f "${DMS_PROJECT_DIR}/compose.yaml" up -d --wait --remove-orphans; then
  echo "docker compose up failed (likely healthcheck or TLS startup). Showing recent container logs:"
  docker compose -f "${DMS_PROJECT_DIR}/compose.yaml" ps || true
  docker logs --tail 120 "${DMS_CONTAINER_NAME}" || true
  exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -Fx "${DMS_CONTAINER_NAME}" >/dev/null 2>&1; then
  echo "Container ${DMS_CONTAINER_NAME} did not start correctly."
  exit 1
fi

#@step "Create primary mailbox account for domain bootstrap"
#@env MAIL_DOMAIN=aiemotion.net
#@env MAIL_PRIMARY_ACCOUNT=postmaster@aiemotion.net
#@env MAIL_PRIMARY_PASSWORD=
#@env DMS_CONTAINER_NAME=mailserver
docker exec "${DMS_CONTAINER_NAME}" setup email add "${MAIL_PRIMARY_ACCOUNT}" "${MAIL_PRIMARY_PASSWORD}"
echo "Primary mailbox created: ${MAIL_PRIMARY_ACCOUNT}"

#@step "Generate DKIM keys in docker-mailserver"
#@env MAIL_DOMAIN=aiemotion.net
#@env DMS_CONTAINER_NAME=mailserver
#@env ROUTE53_DKIM_SELECTOR=mail
#@env DMS_DKIM_KEY_SIZE=2048
echo "Generating DKIM key for ${MAIL_DOMAIN} (selector=${ROUTE53_DKIM_SELECTOR}, keysize=${DMS_DKIM_KEY_SIZE})..."
docker exec "${DMS_CONTAINER_NAME}" setup config dkim domain "${MAIL_DOMAIN}" selector "${ROUTE53_DKIM_SELECTOR}" keysize "${DMS_DKIM_KEY_SIZE}"
echo "Generated DKIM key using explicit domain/selector/keysize options."

docker restart "${DMS_CONTAINER_NAME}" >/dev/null
echo "Restarted ${DMS_CONTAINER_NAME} so new DKIM keys are used for signing."

#@step "Stop mailserver container for DKIM key generation"
#@env DMS_CONTAINER_NAME=mailserver
docker compose -f "${DMS_PROJECT_DIR}/compose.yaml" down

#@step "Apply DKIM DNS record in Route53"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env MAIL_DOMAIN=aiemotion.net
#@env ROUTE53_TTL=300
#@env ROUTE53_DKIM_SELECTOR=mail
#@env DMS_CONTAINER_NAME=mailserver
. ".playbook/lib/mailserver.sh"
init_aws_cmd

ROUTE53_DKIM_FQDN_DNS="${ROUTE53_DKIM_SELECTOR%._domainkey}._domainkey.${MAIL_DOMAIN%.}."
ROUTE53_DKIM_PUBLIC_KEY="$(extract_dkim_public_key "${DMS_CONTAINER_NAME}" "${MAIL_DOMAIN}" "${ROUTE53_DKIM_SELECTOR}" || true)"
add_dkim_record "${ROUTE53_HOSTED_ZONE_ID}" "${MAIL_DOMAIN}" "${ROUTE53_DKIM_SELECTOR}" "${ROUTE53_DKIM_PUBLIC_KEY}" || exit 1
