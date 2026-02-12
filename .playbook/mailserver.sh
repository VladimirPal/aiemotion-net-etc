#@ssh host=root.aiemotion.net

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
#@env ROUTE53_DKIM_PUBLIC_KEY=
#@env ROUTE53_DKIM_AUTO_FROM_CONTAINER=1
#@env DMS_CONTAINER_NAME=mailserver

#@step "Apply base mail DNS records in Route53 (A + MX + SPF + DMARC)"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env ROUTE53_TTL=300
. ".playbook/lib/mailserver.sh"

mailserver_init_aws_cmd

mailserver_add_a_record "${ROUTE53_HOSTED_ZONE_ID}" "${MAILSERVER_FQDN}" "${MAILSERVER_IPV4}" || exit 1
mailserver_add_mx_record "${ROUTE53_HOSTED_ZONE_ID}" "${MAIL_DOMAIN}" "${ROUTE53_MX_PRIORITY}" "${MAILSERVER_FQDN}" || exit 1
mailserver_add_spf_record "${ROUTE53_HOSTED_ZONE_ID}" "${MAIL_DOMAIN}" "${ROUTE53_SPF_VALUE}" || exit 1
mailserver_add_dmarc_record "${ROUTE53_HOSTED_ZONE_ID}" "${MAIL_DOMAIN}" "${ROUTE53_DMARC_NAME}" "${ROUTE53_DMARC_VALUE}" || exit 1

mailserver_show_hetzner_ptr_hint "${MAILSERVER_IPV4}" "${MAILSERVER_FQDN}"

#@step "Start mailserver container for key generation"
#@env DMS_PROJECT_DIR=/etc/mailserver
#@env DMS_CONTAINER_NAME=mailserver
docker compose -f "${DMS_PROJECT_DIR}/compose.yaml" up -d --wait --remove-orphans

if ! docker ps --format '{{.Names}}' | rg -x "${DMS_CONTAINER_NAME}" >/dev/null 2>&1; then
  echo "Container ${DMS_CONTAINER_NAME} did not start correctly."
  exit 1
fi

#@step "Create primary mailbox account for domain bootstrap"
#@env MAIL_DOMAIN=aiemotion.net
#@env MAIL_PRIMARY_ACCOUNT=postmaster@aiemotion.net
#@env MAIL_PRIMARY_PASSWORD=
#@env DMS_CONTAINER_NAME=mailserver
: "${MAIL_DOMAIN:?Set MAIL_DOMAIN via #@env MAIL_DOMAIN=...}"
: "${MAIL_PRIMARY_ACCOUNT:?Set MAIL_PRIMARY_ACCOUNT via #@env MAIL_PRIMARY_ACCOUNT=...}"
: "${MAIL_PRIMARY_PASSWORD:?Set MAIL_PRIMARY_PASSWORD via #@env MAIL_PRIMARY_PASSWORD=...}"
DMS_CONTAINER_NAME="${DMS_CONTAINER_NAME-mailserver}"

if ! printf '%s' "${MAIL_PRIMARY_ACCOUNT}" | rg "@${MAIL_DOMAIN}$" >/dev/null 2>&1; then
  echo "MAIL_PRIMARY_ACCOUNT must belong to MAIL_DOMAIN (${MAIL_DOMAIN})."
  exit 1
fi

if docker exec "${DMS_CONTAINER_NAME}" setup email list 2>/dev/null | rg -x "${MAIL_PRIMARY_ACCOUNT}" >/dev/null 2>&1; then
  echo "Primary mailbox already exists: ${MAIL_PRIMARY_ACCOUNT}"
else
  docker exec "${DMS_CONTAINER_NAME}" setup email add "${MAIL_PRIMARY_ACCOUNT}" "${MAIL_PRIMARY_PASSWORD}"
  echo "Primary mailbox created: ${MAIL_PRIMARY_ACCOUNT}"
fi

#@step "Generate DKIM keys in docker-mailserver"
#@env MAIL_DOMAIN=aiemotion.net
#@env DMS_CONTAINER_NAME=mailserver
#@env ROUTE53_DKIM_SELECTOR=mail
#@env DMS_DKIM_KEY_SIZE=2048
: "${MAIL_DOMAIN:?Set MAIL_DOMAIN via #@env MAIL_DOMAIN=...}"
DMS_CONTAINER_NAME="${DMS_CONTAINER_NAME-mailserver}"
ROUTE53_DKIM_SELECTOR="${ROUTE53_DKIM_SELECTOR-mail}"
DMS_DKIM_KEY_SIZE="${DMS_DKIM_KEY_SIZE-2048}"

if docker exec "${DMS_CONTAINER_NAME}" setup config dkim help >/dev/null 2>&1; then
  if docker exec "${DMS_CONTAINER_NAME}" setup config dkim domain "${MAIL_DOMAIN}" selector "${ROUTE53_DKIM_SELECTOR}" keysize "${DMS_DKIM_KEY_SIZE}"; then
    echo "Generated DKIM key using explicit domain/selector/keysize options."
  else
    echo "Falling back to default DKIM generation command."
    docker exec "${DMS_CONTAINER_NAME}" setup config dkim
  fi
else
  echo "Falling back to default DKIM generation command."
  docker exec "${DMS_CONTAINER_NAME}" setup config dkim
fi

docker restart "${DMS_CONTAINER_NAME}" >/dev/null
echo "Restarted ${DMS_CONTAINER_NAME} so new DKIM keys are used for signing."

#@step "Apply DKIM DNS record in Route53"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env MAIL_DOMAIN=aiemotion.net
#@env ROUTE53_TTL=300
#@env ROUTE53_DKIM_SELECTOR=mail
#@env ROUTE53_DKIM_PUBLIC_KEY=
#@env ROUTE53_DKIM_AUTO_FROM_CONTAINER=1
#@env DMS_CONTAINER_NAME=mailserver
: "${ROUTE53_HOSTED_ZONE_ID:?Set ROUTE53_HOSTED_ZONE_ID via #@env ROUTE53_HOSTED_ZONE_ID=...}"
: "${MAIL_DOMAIN:?Set MAIL_DOMAIN via #@env MAIL_DOMAIN=...}"

AWS_REGION="${AWS_REGION-us-east-1}"
ROUTE53_TTL="${ROUTE53_TTL-300}"
ROUTE53_DKIM_SELECTOR="${ROUTE53_DKIM_SELECTOR-mail}"
ROUTE53_DKIM_AUTO_FROM_CONTAINER="${ROUTE53_DKIM_AUTO_FROM_CONTAINER-1}"
DMS_CONTAINER_NAME="${DMS_CONTAINER_NAME-mailserver}"
mailserver_init_aws_cmd

ROUTE53_DKIM_FQDN_DNS="${ROUTE53_DKIM_SELECTOR%._domainkey}._domainkey.${MAIL_DOMAIN%.}."
if [ -z "${ROUTE53_DKIM_PUBLIC_KEY-}" ] && [ "$ROUTE53_DKIM_AUTO_FROM_CONTAINER" = "1" ]; then
  ROUTE53_DKIM_PUBLIC_KEY="$(mailserver_extract_dkim_public_key "${DMS_CONTAINER_NAME}" "${MAIL_DOMAIN}" "${ROUTE53_DKIM_SELECTOR}" || true)"
fi

: "${ROUTE53_DKIM_PUBLIC_KEY:?Set ROUTE53_DKIM_PUBLIC_KEY (or keep ROUTE53_DKIM_AUTO_FROM_CONTAINER=1 with a generated key)}"
mailserver_add_dkim_record "${ROUTE53_HOSTED_ZONE_ID}" "${MAIL_DOMAIN}" "${ROUTE53_DKIM_SELECTOR}" "${ROUTE53_DKIM_PUBLIC_KEY}" || exit 1

#@step "Verify DNS records (A, MX, SPF, DMARC, DKIM)"
. ".playbook/lib/mailserver.sh"

mailserver_verify_dns_contains "A" "${MAILSERVER_FQDN%.}" "${MAILSERVER_IPV4}" || exit 1
mailserver_verify_dns_contains "MX" "${MAIL_DOMAIN%.}" "${ROUTE53_MX_PRIORITY} ${MAILSERVER_FQDN%.}." || exit 1
mailserver_verify_dns_contains "TXT" "${MAIL_DOMAIN%.}" "${ROUTE53_SPF_VALUE}" || exit 1
mailserver_verify_dns_contains "TXT" "${ROUTE53_DMARC_NAME%.}.${MAIL_DOMAIN%.}" "${ROUTE53_DMARC_VALUE}" || exit 1

if [ -z "${ROUTE53_DKIM_PUBLIC_KEY-}" ] && [ "$ROUTE53_DKIM_AUTO_FROM_CONTAINER" = "1" ]; then
  ROUTE53_DKIM_PUBLIC_KEY="$(mailserver_extract_dkim_public_key "${DMS_CONTAINER_NAME}" "${MAIL_DOMAIN}" "${ROUTE53_DKIM_SELECTOR}" || true)"
fi
: "${ROUTE53_DKIM_PUBLIC_KEY:?Set ROUTE53_DKIM_PUBLIC_KEY (or keep ROUTE53_DKIM_AUTO_FROM_CONTAINER=1 with a generated key)}"
DKIM_KEY_PREFIX="$(printf '%s' "${ROUTE53_DKIM_PUBLIC_KEY}" | cut -c1-24)"
mailserver_verify_dns_contains "TXT" "${ROUTE53_DKIM_SELECTOR%._domainkey}._domainkey.${MAIL_DOMAIN%.}" "v=DKIM1; k=rsa; p=${DKIM_KEY_PREFIX}" || exit 1
