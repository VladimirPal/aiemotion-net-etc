#!/usr/bin/env bash

CHAT_COLOR_MODE="${CHAT_COLOR_MODE-auto}"

chat_colors_enabled=0
case "${CHAT_COLOR_MODE}" in
always) chat_colors_enabled=1 ;;
never) chat_colors_enabled=0 ;;
auto)
  if [ -t 1 ] && [ -z "${NO_COLOR-}" ]; then
    chat_colors_enabled=1
  fi
  ;;
esac

if [ "${chat_colors_enabled}" = "1" ] && [ -z "${NO_COLOR-}" ]; then
  CHAT_COLOR_RED="$(printf '\033[31m')"
  CHAT_COLOR_GREEN="$(printf '\033[32m')"
  CHAT_COLOR_CYAN="$(printf '\033[36m')"
  CHAT_COLOR_RESET="$(printf '\033[0m')"
else
  CHAT_COLOR_RED=""
  CHAT_COLOR_GREEN=""
  CHAT_COLOR_CYAN=""
  CHAT_COLOR_RESET=""
fi

log_info() {
  printf '%s%s%s\n' "${CHAT_COLOR_CYAN}" "$*" "${CHAT_COLOR_RESET}" >&2
}

log_ok() {
  printf '%s%s%s\n' "${CHAT_COLOR_GREEN}" "$*" "${CHAT_COLOR_RESET}" >&2
}

log_error() {
  printf '%s%s%s\n' "${CHAT_COLOR_RED}" "$*" "${CHAT_COLOR_RESET}" >&2
}

init_aws_cmd() {
  CHAT_AWS_CMD=(aws)
  if [ -n "${AWS_PROFILE-}" ]; then
    CHAT_AWS_CMD+=(--profile "${AWS_PROFILE}")
  fi
  if [ -n "${AWS_REGION-}" ]; then
    CHAT_AWS_CMD+=(--region "${AWS_REGION}")
  fi
}

s3_bucket_exists() {
  bucket_name="$1"
  if "${CHAT_AWS_CMD[@]}" s3api head-bucket --bucket "${bucket_name}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

create_s3_bucket() {
  bucket_name="$1"
  region="$2"

  if [ "${region}" = "us-east-1" ]; then
    "${CHAT_AWS_CMD[@]}" s3api create-bucket --bucket "${bucket_name}" >/dev/null
  else
    "${CHAT_AWS_CMD[@]}" s3api create-bucket \
      --bucket "${bucket_name}" \
      --create-bucket-configuration "LocationConstraint=${region}" >/dev/null
  fi
}

ensure_s3_bucket() {
  bucket_name="$1"
  region="$2"

  if s3_bucket_exists "${bucket_name}"; then
    log_ok "S3 bucket already exists: ${bucket_name}"
    return 0
  fi

  log_info "Creating S3 bucket: ${bucket_name}"
  create_s3_bucket "${bucket_name}" "${region}" || return 1
  log_ok "S3 bucket created: ${bucket_name}"
}

ensure_s3_private_public_access_block() {
  bucket_name="$1"
  desired='{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'
  current="$("${CHAT_AWS_CMD[@]}" s3api get-public-access-block \
    --bucket "${bucket_name}" \
    --query "PublicAccessBlockConfiguration" \
    --output json 2>/dev/null || echo "")"

  if [ "${current}" = "${desired}" ]; then
    log_ok "S3 public access block already set for ${bucket_name}"
    return 0
  fi

  log_info "Applying private public-access block for ${bucket_name}"
  "${CHAT_AWS_CMD[@]}" s3api put-public-access-block \
    --bucket "${bucket_name}" \
    --public-access-block-configuration "${desired}" >/dev/null || return 1
  log_ok "S3 public access block configured for ${bucket_name}"
}

ensure_iam_user() {
  iam_user_name="$1"
  if "${CHAT_AWS_CMD[@]}" iam get-user --user-name "${iam_user_name}" >/dev/null 2>&1; then
    log_ok "IAM user already exists: ${iam_user_name}"
    return 0
  fi

  log_info "Creating IAM user: ${iam_user_name}"
  "${CHAT_AWS_CMD[@]}" iam create-user --user-name "${iam_user_name}" >/dev/null
  log_ok "IAM user created: ${iam_user_name}"
}

ensure_iam_policy_for_bucket_and_invalidation() {
  policy_name="$1"
  bucket_name="$2"
  tmp_policy_file="$(mktemp)"

  log_info "Checking IAM policy: ${policy_name}"
  existing_policy_arn="$("${CHAT_AWS_CMD[@]}" iam list-policies \
    --query "Policies[?PolicyName=='${policy_name}'].Arn" \
    --output text)"

  if [ -n "${existing_policy_arn}" ] && [ "${existing_policy_arn}" != "None" ]; then
    log_ok "IAM policy already exists: ${policy_name}"
    printf '%s' "${existing_policy_arn}"
    rm -f "${tmp_policy_file}"
    return 0
  fi

  cat >"${tmp_policy_file}" <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${bucket_name}",
        "arn:aws:s3:::${bucket_name}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateInvalidation"
      ],
      "Resource": "*"
    }
  ]
}
EOF

  log_info "Creating IAM policy: ${policy_name}"
  created_policy_arn="$("${CHAT_AWS_CMD[@]}" iam create-policy \
    --policy-name "${policy_name}" \
    --policy-document "file://${tmp_policy_file}" \
    --query "Policy.Arn" \
    --output text)"
  log_ok "IAM policy created: ${policy_name}"
  rm -f "${tmp_policy_file}"
  printf '%s' "${created_policy_arn}"
}

ensure_iam_policy_attached_to_user() {
  iam_user_name="$1"
  policy_arn="$2"
  attached="$("${CHAT_AWS_CMD[@]}" iam list-attached-user-policies \
    --user-name "${iam_user_name}" \
    --query "AttachedPolicies[?PolicyArn=='${policy_arn}'].PolicyArn" \
    --output text)"

  if [ -n "${attached}" ] && [ "${attached}" != "None" ]; then
    log_ok "IAM policy already attached: ${policy_arn}"
    return 0
  fi

  log_info "Attaching IAM policy to ${iam_user_name}"
  "${CHAT_AWS_CMD[@]}" iam attach-user-policy \
    --user-name "${iam_user_name}" \
    --policy-arn "${policy_arn}" >/dev/null
  log_ok "IAM policy attached: ${policy_arn}"
}

ensure_deploy_iam_access() {
  iam_user_name="$1"
  policy_name="$2"
  bucket_name="$3"

  ensure_iam_user "${iam_user_name}" || return 1
  policy_arn="$(ensure_iam_policy_for_bucket_and_invalidation "${policy_name}" "${bucket_name}")" || return 1
  if [ -z "${policy_arn}" ] || [ "${policy_arn}" = "None" ]; then
    log_error "Failed to resolve IAM policy ARN for ${policy_name}"
    return 1
  fi
  ensure_iam_policy_attached_to_user "${iam_user_name}" "${policy_arn}" || return 1
}

get_certificate_arn_for_domain() {
  domain_name="$1"
  "${CHAT_AWS_CMD[@]}" acm list-certificates \
    --query "CertificateSummaryList[?DomainName=='${domain_name}'].CertificateArn" \
    --output text
}

request_certificate_for_domain() {
  domain_name="$1"
  "${CHAT_AWS_CMD[@]}" acm request-certificate \
    --domain-name "${domain_name}" \
    --validation-method DNS \
    --query "CertificateArn" \
    --output text
}

is_empty_or_none() {
  value="${1-}"
  if [ -z "${value}" ] || [ "${value}" = "None" ] || [ "${value}" = "null" ]; then
    return 0
  fi
  return 1
}

wait_for_acm_validation_record() {
  certificate_arn="$1"
  max_wait_seconds="${2-120}"
  interval_seconds="${3-5}"
  elapsed=0

  log_info "Waiting for ACM DNS validation record (timeout: ${max_wait_seconds}s, interval: ${interval_seconds}s)"
  while [ "${elapsed}" -lt "${max_wait_seconds}" ]; do
    dns_name="$("${CHAT_AWS_CMD[@]}" acm describe-certificate \
      --certificate-arn "${certificate_arn}" \
      --query "Certificate.DomainValidationOptions[0].ResourceRecord.Name" \
      --output text 2>/dev/null)"
    dns_type="$("${CHAT_AWS_CMD[@]}" acm describe-certificate \
      --certificate-arn "${certificate_arn}" \
      --query "Certificate.DomainValidationOptions[0].ResourceRecord.Type" \
      --output text 2>/dev/null)"
    dns_value="$("${CHAT_AWS_CMD[@]}" acm describe-certificate \
      --certificate-arn "${certificate_arn}" \
      --query "Certificate.DomainValidationOptions[0].ResourceRecord.Value" \
      --output text 2>/dev/null)"

    if ! is_empty_or_none "${dns_name}" && ! is_empty_or_none "${dns_type}" && ! is_empty_or_none "${dns_value}"; then
      log_ok "ACM DNS validation record is ready"
      return 0
    fi

    log_info "ACM DNS validation record not ready yet (${elapsed}/${max_wait_seconds}s elapsed); retrying in ${interval_seconds}s"
    sleep "${interval_seconds}"
    elapsed=$((elapsed + interval_seconds))
  done

  log_error "Timed out waiting for ACM DNS validation record: ${certificate_arn}"
  return 1
}

upsert_acm_validation_record() {
  hosted_zone_id="$1"
  certificate_arn="$2"
  ttl="${3-300}"
  tmp_change_batch_local="$(mktemp)"

  dns_name="$("${CHAT_AWS_CMD[@]}" acm describe-certificate \
    --certificate-arn "${certificate_arn}" \
    --query "Certificate.DomainValidationOptions[0].ResourceRecord.Name" \
    --output text)"
  dns_type="$("${CHAT_AWS_CMD[@]}" acm describe-certificate \
    --certificate-arn "${certificate_arn}" \
    --query "Certificate.DomainValidationOptions[0].ResourceRecord.Type" \
    --output text)"
  dns_value="$("${CHAT_AWS_CMD[@]}" acm describe-certificate \
    --certificate-arn "${certificate_arn}" \
    --query "Certificate.DomainValidationOptions[0].ResourceRecord.Value" \
    --output text)"

  if is_empty_or_none "${dns_name}" || is_empty_or_none "${dns_type}" || is_empty_or_none "${dns_value}"; then
    log_error "ACM validation record is not ready yet for certificate ${certificate_arn}"
    rm -f "${tmp_change_batch_local}"
    return 1
  fi

  cat >"${tmp_change_batch_local}" <<EOF
{
  "Comment": "ACM DNS validation record",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${dns_name}",
        "Type": "${dns_type}",
        "TTL": ${ttl},
        "ResourceRecords": [{ "Value": "${dns_value}" }]
      }
    }
  ]
}
EOF

  "${CHAT_AWS_CMD[@]}" route53 change-resource-record-sets \
    --hosted-zone-id "${hosted_zone_id}" \
    --change-batch "file://${tmp_change_batch_local}" >/dev/null
  rm -f "${tmp_change_batch_local}"
}

wait_for_certificate_issued() {
  certificate_arn="$1"
  max_wait_seconds="${2-600}"
  interval_seconds="${3-10}"
  elapsed=0

  log_info "Waiting for ACM certificate status ISSUED (timeout: ${max_wait_seconds}s, interval: ${interval_seconds}s)"
  while [ "${elapsed}" -lt "${max_wait_seconds}" ]; do
    cert_status="$("${CHAT_AWS_CMD[@]}" acm describe-certificate \
      --certificate-arn "${certificate_arn}" \
      --query "Certificate.Status" \
      --output text 2>/dev/null)"

    if [ "${cert_status}" = "ISSUED" ]; then
      return 0
    fi
    if [ "${cert_status}" = "FAILED" ]; then
      log_error "Certificate validation failed: ${certificate_arn}"
      return 1
    fi

    log_info "Current ACM certificate status: ${cert_status:-unknown} (${elapsed}/${max_wait_seconds}s elapsed); next check in ${interval_seconds}s"
    sleep "${interval_seconds}"
    elapsed=$((elapsed + interval_seconds))
  done

  log_error "Timed out waiting for certificate issuance: ${certificate_arn}"
  return 1
}

ensure_certificate_issued() {
  domain_name="$1"
  hosted_zone_id="$2"
  ttl="${3-300}"
  max_wait_seconds="${4-600}"
  interval_seconds="${5-10}"

  certificate_arn="$(get_certificate_arn_for_domain "${domain_name}")"
  if [ -z "${certificate_arn}" ] || [ "${certificate_arn}" = "None" ]; then
    log_info "Requesting ACM certificate for ${domain_name}"
    certificate_arn="$(request_certificate_for_domain "${domain_name}")" || return 1
  fi

  cert_status="$("${CHAT_AWS_CMD[@]}" acm describe-certificate \
    --certificate-arn "${certificate_arn}" \
    --query "Certificate.Status" \
    --output text)"

  if [ "${cert_status}" = "ISSUED" ]; then
    printf '%s' "${certificate_arn}"
    return 0
  fi

  if [ "${cert_status}" = "PENDING_VALIDATION" ]; then
    log_info "Waiting for ACM DNS validation record for ${domain_name}"
    wait_for_acm_validation_record "${certificate_arn}" "${max_wait_seconds}" "${interval_seconds}" || return 1
    log_info "Applying ACM DNS validation record for ${domain_name}"
    upsert_acm_validation_record "${hosted_zone_id}" "${certificate_arn}" "${ttl}" || return 1
  fi

  log_info "Waiting for ACM certificate to become ISSUED"
  wait_for_certificate_issued "${certificate_arn}" "${max_wait_seconds}" "${interval_seconds}" || return 1
  log_ok "ACM certificate issued for ${domain_name}"
  printf '%s' "${certificate_arn}"
}

ensure_cloudfront_oac() {
  bucket_name="$1"
  oac_name="${bucket_name}-OAC"
  log_info "Checking CloudFront OAC: ${oac_name}"
  existing_oac_id="$("${CHAT_AWS_CMD[@]}" cloudfront list-origin-access-controls \
    --query "OriginAccessControlList.Items[?Name=='${oac_name}'].Id" \
    --output text)"

  if [ -n "${existing_oac_id}" ] && [ "${existing_oac_id}" != "None" ]; then
    log_ok "CloudFront OAC already exists: ${oac_name}"
    printf '%s' "${existing_oac_id}"
    return 0
  fi

  log_info "Creating CloudFront OAC: ${oac_name}"
  "${CHAT_AWS_CMD[@]}" cloudfront create-origin-access-control \
    --origin-access-control-config "{
      \"Name\": \"${oac_name}\",
      \"Description\": \"OAC for ${bucket_name}\",
      \"SigningProtocol\": \"sigv4\",
      \"SigningBehavior\": \"always\",
      \"OriginAccessControlOriginType\": \"s3\"
    }" \
    --query "OriginAccessControl.Id" \
    --output text
}

ensure_cloudfront_cors_policy() {
  bucket_name="$1"
  policy_name="${bucket_name}-CORS-Policy"
  log_info "Checking CloudFront response headers policy: ${policy_name}"
  existing_policy_id="$("${CHAT_AWS_CMD[@]}" cloudfront list-response-headers-policies \
    --query "ResponseHeadersPolicyList.Items[?ResponseHeadersPolicy.ResponseHeadersPolicyConfig.Name=='${policy_name}'].ResponseHeadersPolicy.Id" \
    --output text)"

  if [ -n "${existing_policy_id}" ] && [ "${existing_policy_id}" != "None" ]; then
    log_ok "CloudFront response headers policy already exists: ${policy_name}"
    printf '%s' "${existing_policy_id}"
    return 0
  fi

  log_info "Creating CloudFront response headers policy: ${policy_name}"
  "${CHAT_AWS_CMD[@]}" cloudfront create-response-headers-policy \
    --response-headers-policy-config "{
      \"Name\": \"${policy_name}\",
      \"Comment\": \"CORS policy for ${bucket_name}\",
      \"CorsConfig\": {
        \"AccessControlAllowOrigins\": {\"Quantity\": 1, \"Items\": [\"*\"]},
        \"AccessControlAllowMethods\": {\"Quantity\": 2, \"Items\": [\"GET\", \"HEAD\"]},
        \"AccessControlAllowHeaders\": {\"Quantity\": 1, \"Items\": [\"*\"]},
        \"AccessControlExposeHeaders\": {\"Quantity\": 1, \"Items\": [\"ETag\"]},
        \"AccessControlMaxAgeSec\": 86400,
        \"AccessControlAllowCredentials\": false,
        \"OriginOverride\": true
      }
    }" \
    --query "ResponseHeadersPolicy.Id" \
    --output text
}

find_distribution_id_by_alias() {
  domain_name="$1"
  "${CHAT_AWS_CMD[@]}" cloudfront list-distributions \
    --query "DistributionList.Items[?Aliases.Quantity > \`0\` && contains(Aliases.Items, '${domain_name}')].Id" \
    --output text
}

create_cloudfront_distribution() {
  bucket_name="$1"
  domain_name="$2"
  certificate_arn="$3"
  oac_id="$4"
  response_headers_policy_id="$5"
  tmp_config="$(mktemp)"

  cat >"${tmp_config}" <<EOF
{
  "CallerReference": "$(date +%s)-${domain_name}",
  "Comment": "CloudFront distribution for ${domain_name}",
  "Aliases": {
    "Quantity": 1,
    "Items": ["${domain_name}"]
  },
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "${bucket_name}",
        "DomainName": "${bucket_name}.s3.amazonaws.com",
        "OriginAccessControlId": "${oac_id}",
        "S3OriginConfig": { "OriginAccessIdentity": "" }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "${bucket_name}",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["HEAD", "GET"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["HEAD", "GET"]
      }
    },
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": { "Forward": "none" }
    },
    "ResponseHeadersPolicyId": "${response_headers_policy_id}",
    "MinTTL": 0,
    "DefaultTTL": 86400,
    "MaxTTL": 31536000,
    "Compress": true
  },
  "ViewerCertificate": {
    "ACMCertificateArn": "${certificate_arn}",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "Enabled": true,
  "DefaultRootObject": "index.html"
}
EOF

  distribution_id="$("${CHAT_AWS_CMD[@]}" cloudfront create-distribution \
    --distribution-config "file://${tmp_config}" \
    --query "Distribution.Id" \
    --output text)"
  rm -f "${tmp_config}"
  printf '%s' "${distribution_id}"
}

ensure_cloudfront_distribution() {
  bucket_name="$1"
  domain_name="$2"
  certificate_arn="$3"
  oac_id="$4"
  response_headers_policy_id="$5"

  log_info "Checking CloudFront distribution for alias: ${domain_name}"
  distribution_id="$(find_distribution_id_by_alias "${domain_name}")"
  if [ -n "${distribution_id}" ] && [ "${distribution_id}" != "None" ]; then
    log_ok "CloudFront distribution already exists for ${domain_name}: ${distribution_id}"
    printf '%s' "${distribution_id}"
    return 0
  fi

  log_info "Creating CloudFront distribution for ${domain_name}"
  create_cloudfront_distribution \
    "${bucket_name}" \
    "${domain_name}" \
    "${certificate_arn}" \
    "${oac_id}" \
    "${response_headers_policy_id}"
}

reconcile_cloudfront_distribution_config() {
  distribution_id="$1"
  bucket_name="$2"
  domain_name="$3"
  certificate_arn="$4"
  oac_id="$5"
  response_headers_policy_id="$6"
  config_file="$(mktemp)"
  updated_file="$(mktemp)"
  needs_update=0

  "${CHAT_AWS_CMD[@]}" cloudfront get-distribution-config \
    --id "${distribution_id}" \
    --query "DistributionConfig" >"${config_file}"

  current_oac_id="$(jq -r '.Origins.Items[0].OriginAccessControlId // empty' "${config_file}")"
  current_domain_name="$(jq -r '.Origins.Items[0].DomainName // empty' "${config_file}")"
  current_cert_arn="$(jq -r '.ViewerCertificate.ACMCertificateArn // empty' "${config_file}")"
  current_alias="$(jq -r '.Aliases.Items[0] // empty' "${config_file}")"
  current_root_object="$(jq -r '.DefaultRootObject // empty' "${config_file}")"
  current_response_headers_policy_id="$(jq -r '.DefaultCacheBehavior.ResponseHeadersPolicyId // empty' "${config_file}")"

  expected_origin_domain="${bucket_name}.s3.amazonaws.com"
  if [ "${current_oac_id}" != "${oac_id}" ]; then
    needs_update=1
  fi
  if [ "${current_domain_name}" != "${expected_origin_domain}" ]; then
    needs_update=1
  fi
  if [ "${current_cert_arn}" != "${certificate_arn}" ]; then
    needs_update=1
  fi
  if [ "${current_alias}" != "${domain_name}" ]; then
    needs_update=1
  fi
  if [ "${current_root_object}" != "index.html" ]; then
    needs_update=1
  fi
  if [ "${current_response_headers_policy_id}" != "${response_headers_policy_id}" ]; then
    needs_update=1
  fi

  if [ "${needs_update}" -eq 0 ]; then
    log_ok "CloudFront distribution config already in desired state: ${distribution_id}"
    rm -f "${config_file}" "${updated_file}"
    return 0
  fi

  log_info "Reconciling CloudFront distribution config: ${distribution_id}"
  jq \
    --arg origin_domain "${expected_origin_domain}" \
    --arg alias "${domain_name}" \
    --arg cert_arn "${certificate_arn}" \
    --arg oac "${oac_id}" \
    --arg response_policy "${response_headers_policy_id}" \
    '.Origins.Items[0].DomainName = $origin_domain
    | .Aliases.Quantity = 1
    | .Aliases.Items = [$alias]
    | .ViewerCertificate.ACMCertificateArn = $cert_arn
    | .Origins.Items[0].OriginAccessControlId = $oac
    | .DefaultRootObject = "index.html"
    | .DefaultCacheBehavior.ResponseHeadersPolicyId = $response_policy' \
    "${config_file}" >"${updated_file}"

  etag="$("${CHAT_AWS_CMD[@]}" cloudfront get-distribution-config \
    --id "${distribution_id}" \
    --query "ETag" \
    --output text)"

  "${CHAT_AWS_CMD[@]}" cloudfront update-distribution \
    --id "${distribution_id}" \
    --distribution-config "file://${updated_file}" \
    --if-match "${etag}" >/dev/null
  log_ok "CloudFront distribution update request submitted: ${distribution_id}"

  rm -f "${config_file}" "${updated_file}"
}

ensure_s3_policy_for_cloudfront_distribution() {
  bucket_name="$1"
  distribution_id="$2"
  log_info "Preparing S3 bucket policy for CloudFront distribution ${distribution_id}"
  account_id="$("${CHAT_AWS_CMD[@]}" sts get-caller-identity --query "Account" --output text)"
  source_arn="arn:aws:cloudfront::${account_id}:distribution/${distribution_id}"
  tmp_policy="$(mktemp)"

  cat >"${tmp_policy}" <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${bucket_name}/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "${source_arn}"
        }
      }
    }
  ]
}
EOF

  "${CHAT_AWS_CMD[@]}" s3api put-bucket-policy \
    --bucket "${bucket_name}" \
    --policy "file://${tmp_policy}" >/dev/null
  log_ok "S3 bucket policy applied: ${bucket_name}"
  rm -f "${tmp_policy}"
}

ensure_usercontent_behavior() {
  distribution_id="$1"
  bucket_name="$2"
  config_file="$(mktemp)"
  updated_file="$(mktemp)"

  log_info "Checking /usercontent/* behavior on distribution ${distribution_id}"
  "${CHAT_AWS_CMD[@]}" cloudfront get-distribution-config \
    --id "${distribution_id}" \
    --query "DistributionConfig" >"${config_file}"

  if jq -e '.CacheBehaviors.Items[]? | select(.PathPattern == "/usercontent/*")' "${config_file}" >/dev/null 2>&1; then
    log_ok "/usercontent/* behavior already present on ${distribution_id}"
    rm -f "${config_file}" "${updated_file}"
    return 0
  fi

  log_info "Adding /usercontent/* behavior to distribution ${distribution_id}"
  jq --arg origin "${bucket_name}" '.CacheBehaviors.Items += [{
      "PathPattern": "/usercontent/*",
      "TargetOriginId": $origin,
      "ViewerProtocolPolicy": "redirect-to-https",
      "AllowedMethods": {
        "Quantity": 2,
        "Items": ["HEAD", "GET"],
        "CachedMethods": {
          "Quantity": 2,
          "Items": ["HEAD", "GET"]
        }
      },
      "ForwardedValues": {
        "QueryString": false,
        "QueryStringCacheKeys": {"Quantity": 0, "Items": []},
        "Headers": {"Quantity": 0, "Items": []},
        "Cookies": {"Forward": "none"}
      },
      "LambdaFunctionAssociations": {"Quantity": 0},
      "FunctionAssociations": {"Quantity": 0},
      "MinTTL": 0,
      "DefaultTTL": 86400,
      "MaxTTL": 31536000,
      "Compress": true,
      "FieldLevelEncryptionId": "",
      "SmoothStreaming": false
    }] | .CacheBehaviors.Quantity += 1' "${config_file}" >"${updated_file}"

  etag="$("${CHAT_AWS_CMD[@]}" cloudfront get-distribution-config \
    --id "${distribution_id}" \
    --query "ETag" \
    --output text)"

  "${CHAT_AWS_CMD[@]}" cloudfront update-distribution \
    --id "${distribution_id}" \
    --distribution-config "file://${updated_file}" \
    --if-match "${etag}" >/dev/null
  log_ok "/usercontent/* behavior update submitted for ${distribution_id}"

  rm -f "${config_file}" "${updated_file}"
}

get_cloudfront_domain() {
  distribution_id="$1"
  "${CHAT_AWS_CMD[@]}" cloudfront get-distribution \
    --id "${distribution_id}" \
    --query 'Distribution.DomainName' \
    --output text
}

upsert_route53_alias_to_cloudfront() {
  hosted_zone_id="$1"
  record_name="$2"
  cloudfront_domain="$3"
  tmp_change_batch_local="$(mktemp)"

  log_info "Applying Route53 alias: ${record_name} -> ${cloudfront_domain}"
  cat >"${tmp_change_batch_local}" <<EOF
{
  "Comment": "Alias ${record_name} -> ${cloudfront_domain}",
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "${record_name%.}.",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z2FDTNDATAQYW2",
          "DNSName": "${cloudfront_domain%.}.",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF

  "${CHAT_AWS_CMD[@]}" route53 change-resource-record-sets \
    --hosted-zone-id "${hosted_zone_id}" \
    --change-batch "file://${tmp_change_batch_local}"
  log_ok "Route53 alias UPSERT submitted for ${record_name}"
  rm -f "${tmp_change_batch_local}"
}

show_default_behavior() {
  distribution_id="$1"
  "${CHAT_AWS_CMD[@]}" cloudfront get-distribution-config \
    --id "${distribution_id}" \
    --query "DistributionConfig.DefaultCacheBehavior.{TargetOriginId:TargetOriginId,ViewerProtocolPolicy:ViewerProtocolPolicy,ResponseHeadersPolicyId:ResponseHeadersPolicyId}" \
    --output table
}

show_additional_behaviors() {
  distribution_id="$1"
  "${CHAT_AWS_CMD[@]}" cloudfront get-distribution-config \
    --id "${distribution_id}" \
    --query "DistributionConfig.CacheBehaviors.Items[].{PathPattern:PathPattern,TargetOriginId:TargetOriginId,ViewerProtocolPolicy:ViewerProtocolPolicy,ResponseHeadersPolicyId:ResponseHeadersPolicyId}" \
    --output table
}

verify_usercontent_only_behavior() {
  distribution_id="$1"
  path_patterns="$("${CHAT_AWS_CMD[@]}" cloudfront get-distribution-config \
    --id "${distribution_id}" \
    --query "DistributionConfig.CacheBehaviors.Items[].PathPattern" \
    --output text)"

  if [ -z "${path_patterns}" ]; then
    log_error "No additional cache behaviors found. Expected: /usercontent/*"
    return 1
  fi

  if [ "${path_patterns}" = "/usercontent/*" ]; then
    log_ok "Verified additional behavior list contains only /usercontent/*"
    return 0
  fi

  log_error "Unexpected additional behaviors: ${path_patterns}"
  log_error "Expected exactly one path pattern: /usercontent/*"
  return 1
}
