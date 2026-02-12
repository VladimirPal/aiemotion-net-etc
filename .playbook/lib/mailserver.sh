#!/usr/bin/env bash

MAILSERVER_COLOR_MODE="${MAILSERVER_COLOR_MODE-always}"

mailserver_colors_enabled=0
case "${MAILSERVER_COLOR_MODE}" in
always) mailserver_colors_enabled=1 ;;
never) mailserver_colors_enabled=0 ;;
auto)
  if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then
    mailserver_colors_enabled=1
  fi
  ;;
esac

if [ "$mailserver_colors_enabled" = "1" ] && [ -z "${NO_COLOR-}" ]; then
  MAILSERVER_COLOR_RED="$(printf '\033[31m')"
  MAILSERVER_COLOR_GREEN="$(printf '\033[32m')"
  MAILSERVER_COLOR_YELLOW="$(printf '\033[33m')"
  MAILSERVER_COLOR_CYAN="$(printf '\033[36m')"
  MAILSERVER_COLOR_RESET="$(printf '\033[0m')"
else
  MAILSERVER_COLOR_RED=""
  MAILSERVER_COLOR_GREEN=""
  MAILSERVER_COLOR_YELLOW=""
  MAILSERVER_COLOR_CYAN=""
  MAILSERVER_COLOR_RESET=""
fi

log_info() {
  printf '%s%s%s\n' "${MAILSERVER_COLOR_CYAN}" "$*" "${MAILSERVER_COLOR_RESET}"
}

log_ok() {
  printf '%s%s%s\n' "${MAILSERVER_COLOR_GREEN}" "$*" "${MAILSERVER_COLOR_RESET}"
}

log_warn() {
  printf '%s%s%s\n' "${MAILSERVER_COLOR_YELLOW}" "$*" "${MAILSERVER_COLOR_RESET}"
}

log_error() {
  printf '%s%s%s\n' "${MAILSERVER_COLOR_RED}" "$*" "${MAILSERVER_COLOR_RESET}"
}

dns_fqdn() {
  printf '%s.' "${1%.}"
}

normalize_txt_value() {
  txt_value="$1"
  case "$txt_value" in
  \"*\")
    txt_value="${txt_value#\"}"
    txt_value="${txt_value%\"}"
    ;;
  \'*\')
    txt_value="${txt_value#\'}"
    txt_value="${txt_value%\'}"
    ;;
  esac
  # Some env parsers inject quotes inside the value, e.g. v="spf1 ... -all".
  # Route53 TXT payload is wrapped with quotes by this playbook, so strip raw quotes here.
  txt_value="${txt_value//\"/}"
  txt_value="${txt_value//\'/}"
  printf '%s' "$txt_value"
}

init_aws_cmd() {
  AWS_CMD=(aws)
  if [ -n "${AWS_PROFILE-}" ]; then
    AWS_CMD+=(--profile "${AWS_PROFILE}")
  fi
}

route53_upsert_plain_record() {
  zone_id="$1"
  record_name="$2"
  record_type="$3"
  record_value="$4"
  tmp_change_batch_local="$(mktemp)"
  cat >"$tmp_change_batch_local" <<EOF
{
  "Comment": "Mail DNS record managed by playbook",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${record_name}",
        "Type": "${record_type}",
        "TTL": ${ROUTE53_TTL},
        "ResourceRecords": [{ "Value": "${record_value}" }]
      }
    }
  ]
}
EOF
  "${AWS_CMD[@]}" route53 change-resource-record-sets --region "${AWS_REGION}" --hosted-zone-id "${zone_id}" --change-batch "file://${tmp_change_batch_local}"
  rm -f "$tmp_change_batch_local"
}

route53_upsert_txt_record() {
  zone_id="$1"
  record_name="$2"
  record_value="$(normalize_txt_value "$3")"
  txt_route53_value=""

  while IFS= read -r txt_chunk || [ -n "$txt_chunk" ]; do
    txt_chunk_json="${txt_chunk//\\/\\\\}"
    txt_chunk_json="${txt_chunk_json//\"/\\\"}"
    if [ -z "$txt_route53_value" ]; then
      txt_route53_value="\\\"${txt_chunk_json}\\\""
    else
      txt_route53_value="${txt_route53_value} \\\"${txt_chunk_json}\\\""
    fi
  done <<EOF
$(printf '%s' "$record_value" | fold -w 255)
EOF

  if [ -z "$txt_route53_value" ]; then
    txt_route53_value='\"\"'
  fi
  tmp_change_batch_local="$(mktemp)"
  cat >"$tmp_change_batch_local" <<EOF
{
  "Comment": "Mail TXT record managed by playbook",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${record_name}",
        "Type": "TXT",
        "TTL": ${ROUTE53_TTL},
        "ResourceRecords": [{ "Value": "${txt_route53_value}" }]
      }
    }
  ]
}
EOF
  "${AWS_CMD[@]}" route53 change-resource-record-sets --region "${AWS_REGION}" --hosted-zone-id "${zone_id}" --change-batch "file://${tmp_change_batch_local}"
  rm -f "$tmp_change_batch_local"
}

extract_dkim_public_key() {
  dms_container_name="$1"
  mail_domain="$2"
  dkim_selector="$3"
  dkim_config_dir="${DMS_CONFIG_DIR:-/etc/mailserver/docker-data/dms/config}"
  dkim_txt_path="${dkim_config_dir%/}/opendkim/keys/${mail_domain}/${dkim_selector}.txt"
  dkim_record_raw="$(cat "${dkim_txt_path}" 2>/dev/null || true)"
  if [ -z "$dkim_record_raw" ]; then
    return 1
  fi
  dkim_record_flat="$(printf '%s' "$dkim_record_raw" | tr -d '\n\r\t \"()')"
  printf '%s' "$dkim_record_flat" | sed -E 's/.*p=([^;]+).*/\1/'
}

add_a_record() {
  zone_id="$1"
  host_fqdn="$2"
  ipv4="$3"
  host_dns="$(dns_fqdn "${host_fqdn}")"
  route53_upsert_plain_record "${zone_id}" "${host_dns}" "A" "${ipv4}" || return 1
  echo "A record upsert submitted: ${host_dns} -> ${ipv4}"
}

add_mx_record() {
  zone_id="$1"
  mail_domain="$2"
  mx_priority="$3"
  mx_target_fqdn="$4"
  mail_domain_dns="$(dns_fqdn "${mail_domain}")"
  mx_target_dns="$(dns_fqdn "${mx_target_fqdn}")"
  route53_upsert_plain_record "${zone_id}" "${mail_domain_dns}" "MX" "${mx_priority} ${mx_target_dns}" || return 1
  echo "MX record upsert submitted: ${mail_domain_dns} -> ${mx_priority} ${mx_target_dns}"
}

add_spf_record() {
  zone_id="$1"
  mail_domain="$2"
  spf_value="$(normalize_txt_value "$3")"
  mail_domain_dns="$(dns_fqdn "${mail_domain}")"
  route53_upsert_txt_record "${zone_id}" "${mail_domain_dns}" "${spf_value}" || return 1
  echo "SPF TXT upsert submitted for ${mail_domain_dns}"
}

add_dmarc_record() {
  zone_id="$1"
  mail_domain="$2"
  dmarc_name="$3"
  dmarc_value="$(normalize_txt_value "$4")"
  dmarc_dns="$(dns_fqdn "${dmarc_name%.}.${mail_domain%.}")"
  route53_upsert_txt_record "${zone_id}" "${dmarc_dns}" "${dmarc_value}" || return 1
  echo "DMARC TXT upsert submitted for ${dmarc_dns}"
}

add_dkim_record() {
  zone_id="$1"
  mail_domain="$2"
  dkim_selector="$3"
  dkim_public_key="$4"
  dkim_selector_label="${dkim_selector%._domainkey}"
  dkim_dns="$(dns_fqdn "${dkim_selector_label}._domainkey.${mail_domain%.}")"
  route53_upsert_txt_record "${zone_id}" "${dkim_dns}" "v=DKIM1; h=sha256; k=rsa; p=${dkim_public_key}" || return 1
  echo "DKIM TXT upsert submitted for ${dkim_dns}"
}

show_hetzner_ptr_hint() {
  ipv4="$1"
  host_fqdn="$2"
  ptr_record_name="$(printf '%s' "${ipv4}" | awk -F. '{print $4"."$3"."$2"."$1".in-addr.arpa."}')"
  echo "PTR must be set manually in Hetzner Cloud/Robot:"
  echo "  IP: ${ipv4}"
  echo "  PTR value to configure: ${host_fqdn%.}"
  echo "  Reverse zone record (reference): ${ptr_record_name}"
}

verify_dns_contains() {
  record_type="$1"
  record_name="$2"
  expected_value="$3"
  dns_server="${4-1.1.1.1}"
  dig_timeout_seconds="${5-2}"
  dig_tries="${6-1}"

  log_info "Checking ${record_type} ${record_name}..."
  current_output="$(dig @"${dns_server}" +short +time="${dig_timeout_seconds}" +tries="${dig_tries}" "${record_type}" "${record_name}" 2>/dev/null || true)"
  if [ "${record_type}" = "TXT" ]; then
    current_matchable="$(printf '%s' "${current_output}" | tr -d '"')"
    expected_matchable="$(normalize_txt_value "${expected_value}")"
  else
    current_matchable="${current_output}"
    expected_matchable="${expected_value}"
  fi

  if printf '%s' "${current_matchable}" | grep -F -- "${expected_matchable}" >/dev/null 2>&1; then
    log_ok "Verified ${record_type} ${record_name} contains: ${expected_matchable}"
    return 0
  fi

  log_error "DNS verification failed for ${record_type} ${record_name}"
  log_warn "Expected to contain: ${expected_matchable}"
  log_warn "Current response:"
  printf '%s\n' "${current_output}"
  return 1
}

mailserver_create_team_mailboxes() {
  dms_container_name="$1"
  mail_domain="$2"
  password_mrv="$3"
  password_akhat="$4"
  password_nordin="$5"

  log_info "Creating person mailboxes in ${dms_container_name} for ${mail_domain}..."
  docker exec "${dms_container_name}" setup email add "mrv@${mail_domain}" "${password_mrv}"
  log_ok "Mailbox ensured: mrv@${mail_domain}"
  docker exec "${dms_container_name}" setup email add "akhat@${mail_domain}" "${password_akhat}"
  log_ok "Mailbox ensured: akhat@${mail_domain}"
  docker exec "${dms_container_name}" setup email add "nordin@${mail_domain}" "${password_nordin}"
  log_ok "Mailbox ensured: nordin@${mail_domain}"
  log_ok "Person mailbox setup completed for ${mail_domain}"
}

mailserver_create_operator_forwarding() {
  dms_container_name="$1"
  mail_domain="$2"

  log_info "Creating forwarding aliases to operator@${mail_domain}..."
  if docker exec "${dms_container_name}" setup alias add "hello@${mail_domain}" "operator@${mail_domain}"; then
    log_ok "Forwarding ensured: hello@${mail_domain} -> operator@${mail_domain}"
  else
    log_error "Failed to add forwarding for hello@${mail_domain} (it may already exist as a mailbox account)."
    return 1
  fi
  if docker exec "${dms_container_name}" setup alias add "support@${mail_domain}" "operator@${mail_domain}"; then
    log_ok "Forwarding ensured: support@${mail_domain} -> operator@${mail_domain}"
  else
    log_error "Failed to add forwarding for support@${mail_domain} (it may already exist as a mailbox account)."
    return 1
  fi
  log_ok "Operator forwarding setup completed for ${mail_domain}"
}

mailserver_ensure_recipient_bcc_maps_enabled() {
  dms_container_name="$1"
  postfix_main_cf_path="$2"
  recipient_bcc_path="$3"

  if docker exec "${dms_container_name}" sh -c "grep -Eq '^[[:space:]]*recipient_bcc_maps[[:space:]]*=' '${postfix_main_cf_path}'"; then
    docker exec "${dms_container_name}" sh -c "sed -i -E 's|^[[:space:]]*recipient_bcc_maps[[:space:]]*=.*|recipient_bcc_maps = hash:${recipient_bcc_path}|' '${postfix_main_cf_path}'"
  else
    docker exec "${dms_container_name}" sh -c "printf '\nrecipient_bcc_maps = hash:${recipient_bcc_path}\n' >> '${postfix_main_cf_path}'"
  fi
}

mailserver_upsert_recipient_bcc_entry() {
  dms_container_name="$1"
  recipient_bcc_path="$2"
  source_address="$3"
  target_address="$4"

  docker exec "${dms_container_name}" sh -c "touch '${recipient_bcc_path}'"
  docker exec "${dms_container_name}" sh -c "awk -v src='${source_address}' -v dst='${target_address}' '
BEGIN { updated = 0 }
\$1 == src { print src \" \" dst; updated = 1; next }
{ print }
END { if (!updated) print src \" \" dst }
' '${recipient_bcc_path}' > '${recipient_bcc_path}.tmp' && mv '${recipient_bcc_path}.tmp' '${recipient_bcc_path}'"
}

mailserver_configure_operator_mailbox_forwarding() {
  dms_container_name="$1"
  mail_domain="$2"
  dms_config_dir="${3-/tmp/docker-mailserver}"
  postfix_main_cf_path="${dms_config_dir%/}/postfix-main.cf"
  recipient_bcc_path="${dms_config_dir%/}/postfix-recipient_bcc"

  log_info "Configuring mailbox-level forwarding (recipient BCC) to operator@${mail_domain}..."

  mailserver_ensure_recipient_bcc_maps_enabled "${dms_container_name}" "${postfix_main_cf_path}" "${recipient_bcc_path}"
  mailserver_upsert_recipient_bcc_entry "${dms_container_name}" "${recipient_bcc_path}" "hello@${mail_domain}" "operator@${mail_domain}"
  mailserver_upsert_recipient_bcc_entry "${dms_container_name}" "${recipient_bcc_path}" "support@${mail_domain}" "operator@${mail_domain}"
  log_ok "Upserted forwarding map entries in ${recipient_bcc_path}"

  docker exec "${dms_container_name}" postmap "${recipient_bcc_path}"
  docker exec "${dms_container_name}" postfix reload
  log_ok "Mailbox-level forwarding enabled: hello/support -> operator for ${mail_domain}"
}

mailserver_configure_admin_mailbox_forwarding() {
  dms_container_name="$1"
  mail_domain="$2"
  dms_config_dir="${3-/tmp/docker-mailserver}"
  postfix_main_cf_path="${dms_config_dir%/}/postfix-main.cf"
  recipient_bcc_path="${dms_config_dir%/}/postfix-recipient_bcc"

  log_info "Configuring mailbox-level forwarding (recipient BCC) to admin@${mail_domain}..."

  mailserver_ensure_recipient_bcc_maps_enabled "${dms_container_name}" "${postfix_main_cf_path}" "${recipient_bcc_path}"
  mailserver_upsert_recipient_bcc_entry "${dms_container_name}" "${recipient_bcc_path}" "billing@${mail_domain}" "admin@${mail_domain}"
  mailserver_upsert_recipient_bcc_entry "${dms_container_name}" "${recipient_bcc_path}" "meta@${mail_domain}" "admin@${mail_domain}"
  log_ok "Upserted forwarding map entries in ${recipient_bcc_path}"

  docker exec "${dms_container_name}" postmap "${recipient_bcc_path}"
  docker exec "${dms_container_name}" postfix reload
  log_ok "Mailbox-level forwarding enabled: billing/meta -> admin for ${mail_domain}"
}

mailserver_log_info() { log_info "$@"; }
mailserver_log_ok() { log_ok "$@"; }
mailserver_log_warn() { log_warn "$@"; }
mailserver_log_error() { log_error "$@"; }
mailserver_dns_fqdn() { dns_fqdn "$@"; }
mailserver_normalize_txt_value() { normalize_txt_value "$@"; }
mailserver_init_aws_cmd() { init_aws_cmd "$@"; }
mailserver_route53_upsert_plain_record() { route53_upsert_plain_record "$@"; }
mailserver_route53_upsert_txt_record() { route53_upsert_txt_record "$@"; }
mailserver_extract_dkim_public_key() { extract_dkim_public_key "$@"; }
mailserver_add_a_record() { add_a_record "$@"; }
mailserver_add_mx_record() { add_mx_record "$@"; }
mailserver_add_spf_record() { add_spf_record "$@"; }
mailserver_add_dmarc_record() { add_dmarc_record "$@"; }
mailserver_add_dkim_record() { add_dkim_record "$@"; }
mailserver_show_hetzner_ptr_hint() { show_hetzner_ptr_hint "$@"; }
mailserver_verify_dns_contains() { verify_dns_contains "$@"; }
mailserver_mailbox_create_team_mailboxes() { mailserver_create_team_mailboxes "$@"; }
mailserver_mailbox_create_operator_forwarding() { mailserver_create_operator_forwarding "$@"; }
mailserver_mailbox_configure_operator_forwarding() { mailserver_configure_operator_mailbox_forwarding "$@"; }
mailserver_mailbox_configure_admin_forwarding() { mailserver_configure_admin_mailbox_forwarding "$@"; }
