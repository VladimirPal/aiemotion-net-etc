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

mailserver_log_info() {
  printf '%s%s%s\n' "${MAILSERVER_COLOR_CYAN}" "$*" "${MAILSERVER_COLOR_RESET}"
}

mailserver_log_ok() {
  printf '%s%s%s\n' "${MAILSERVER_COLOR_GREEN}" "$*" "${MAILSERVER_COLOR_RESET}"
}

mailserver_log_warn() {
  printf '%s%s%s\n' "${MAILSERVER_COLOR_YELLOW}" "$*" "${MAILSERVER_COLOR_RESET}"
}

mailserver_log_error() {
  printf '%s%s%s\n' "${MAILSERVER_COLOR_RED}" "$*" "${MAILSERVER_COLOR_RESET}"
}

mailserver_dns_fqdn() {
  printf '%s.' "${1%.}"
}

mailserver_normalize_txt_value() {
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

mailserver_init_aws_cmd() {
  AWS_CMD=(aws)
  if [ -n "${AWS_PROFILE-}" ]; then
    AWS_CMD+=(--profile "${AWS_PROFILE}")
  fi
}

mailserver_route53_upsert_plain_record() {
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

mailserver_route53_upsert_txt_record() {
  zone_id="$1"
  record_name="$2"
  record_value="$(mailserver_normalize_txt_value "$3")"
  record_value_json="${record_value//\\/\\\\}"
  record_value_json="${record_value_json//\"/\\\"}"
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
        "ResourceRecords": [{ "Value": "\"${record_value_json}\"" }]
      }
    }
  ]
}
EOF
  "${AWS_CMD[@]}" route53 change-resource-record-sets --region "${AWS_REGION}" --hosted-zone-id "${zone_id}" --change-batch "file://${tmp_change_batch_local}"
  rm -f "$tmp_change_batch_local"
}

mailserver_extract_dkim_public_key() {
  dms_container_name="$1"
  mail_domain="$2"
  dkim_selector="$3"
  dkim_record_raw="$(docker exec "${dms_container_name}" sh -lc "cat /tmp/docker-mailserver/opendkim/keys/${mail_domain}/${dkim_selector}.txt" 2>/dev/null || true)"
  if [ -z "$dkim_record_raw" ]; then
    return 1
  fi
  printf '%s' "$dkim_record_raw" | tr -d '\n' | sed -E 's/.*p=([^\"; )]+).*/\1/'
}

mailserver_add_a_record() {
  zone_id="$1"
  host_fqdn="$2"
  ipv4="$3"
  host_dns="$(mailserver_dns_fqdn "${host_fqdn}")"
  mailserver_route53_upsert_plain_record "${zone_id}" "${host_dns}" "A" "${ipv4}" || return 1
  echo "A record upsert submitted: ${host_dns} -> ${ipv4}"
}

mailserver_add_mx_record() {
  zone_id="$1"
  mail_domain="$2"
  mx_priority="$3"
  mx_target_fqdn="$4"
  mail_domain_dns="$(mailserver_dns_fqdn "${mail_domain}")"
  mx_target_dns="$(mailserver_dns_fqdn "${mx_target_fqdn}")"
  mailserver_route53_upsert_plain_record "${zone_id}" "${mail_domain_dns}" "MX" "${mx_priority} ${mx_target_dns}" || return 1
  echo "MX record upsert submitted: ${mail_domain_dns} -> ${mx_priority} ${mx_target_dns}"
}

mailserver_add_spf_record() {
  zone_id="$1"
  mail_domain="$2"
  spf_value="$(mailserver_normalize_txt_value "$3")"
  mail_domain_dns="$(mailserver_dns_fqdn "${mail_domain}")"
  mailserver_route53_upsert_txt_record "${zone_id}" "${mail_domain_dns}" "${spf_value}" || return 1
  echo "SPF TXT upsert submitted for ${mail_domain_dns}"
}

mailserver_add_dmarc_record() {
  zone_id="$1"
  mail_domain="$2"
  dmarc_name="$3"
  dmarc_value="$(mailserver_normalize_txt_value "$4")"
  dmarc_dns="$(mailserver_dns_fqdn "${dmarc_name%.}.${mail_domain%.}")"
  mailserver_route53_upsert_txt_record "${zone_id}" "${dmarc_dns}" "${dmarc_value}" || return 1
  echo "DMARC TXT upsert submitted for ${dmarc_dns}"
}

mailserver_add_dkim_record() {
  zone_id="$1"
  mail_domain="$2"
  dkim_selector="$3"
  dkim_public_key="$4"
  dkim_selector_label="${dkim_selector%._domainkey}"
  dkim_dns="$(mailserver_dns_fqdn "${dkim_selector_label}._domainkey.${mail_domain%.}")"
  mailserver_route53_upsert_txt_record "${zone_id}" "${dkim_dns}" "v=DKIM1; k=rsa; p=${dkim_public_key}" || return 1
  echo "DKIM TXT upsert submitted for ${dkim_dns}"
}

mailserver_show_hetzner_ptr_hint() {
  ipv4="$1"
  host_fqdn="$2"
  ptr_record_name="$(printf '%s' "${ipv4}" | awk -F. '{print $4"."$3"."$2"."$1".in-addr.arpa."}')"
  echo "PTR must be set manually in Hetzner Cloud/Robot:"
  echo "  IP: ${ipv4}"
  echo "  PTR value to configure: ${host_fqdn%.}"
  echo "  Reverse zone record (reference): ${ptr_record_name}"
}

mailserver_verify_dns_contains() {
  record_type="$1"
  record_name="$2"
  expected_value="$3"
  dns_server="${4-1.1.1.1}"
  dig_timeout_seconds="${5-2}"
  dig_tries="${6-1}"

  mailserver_log_info "Checking ${record_type} ${record_name}..."
  current_output="$(dig @"${dns_server}" +short +time="${dig_timeout_seconds}" +tries="${dig_tries}" "${record_type}" "${record_name}" 2>/dev/null || true)"
  if [ "${record_type}" = "TXT" ]; then
    current_matchable="$(printf '%s' "${current_output}" | tr -d '"')"
    expected_matchable="$(mailserver_normalize_txt_value "${expected_value}")"
  else
    current_matchable="${current_output}"
    expected_matchable="${expected_value}"
  fi

  if printf '%s' "${current_matchable}" | grep -F -- "${expected_matchable}" >/dev/null 2>&1; then
    mailserver_log_ok "Verified ${record_type} ${record_name} contains: ${expected_matchable}"
    return 0
  fi

  mailserver_log_error "DNS verification failed for ${record_type} ${record_name}"
  mailserver_log_warn "Expected to contain: ${expected_matchable}"
  mailserver_log_warn "Current response:"
  printf '%s\n' "${current_output}"
  return 1
}
