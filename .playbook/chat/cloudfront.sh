#@group "S3 bucket for chat client"

#@step "Ensure private S3 bucket exists for chat client"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env CHAT_BUCKET_NAME=chat-aiemotion-net
. ".playbook/lib/chat.sh"
init_aws_cmd

ensure_s3_bucket "${CHAT_BUCKET_NAME}" "${AWS_REGION}" || exit 1
ensure_s3_private_public_access_block "${CHAT_BUCKET_NAME}" || exit 1

#@group "IAM deploy access"

#@step "Ensure deploy IAM user and policy for S3 + CloudFront invalidation"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env CHAT_BUCKET_NAME=chat-aiemotion-net
#@env CHAT_IAM_USER_NAME=deploy-user-chat-aiemotion-net
#@env CHAT_IAM_POLICY_NAME=S3CloudFrontDeployPolicy-chat-aiemotion-net
. ".playbook/lib/chat.sh"
init_aws_cmd

ensure_deploy_iam_access "${CHAT_IAM_USER_NAME}" "${CHAT_IAM_POLICY_NAME}" "${CHAT_BUCKET_NAME}" || exit 1

#@group "CloudFront setup for chat.aiemotion.net"

#@step "Issue/validate ACM certificate for chat.aiemotion.net"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env ROUTE53_TTL=300
#@env ACM_MAX_WAIT_SECONDS=600
#@env ACM_WAIT_INTERVAL_SECONDS=10
#@env CHAT_DOMAIN=chat.aiemotion.net
. ".playbook/lib/chat.sh"
init_aws_cmd

CHAT_CERTIFICATE_ARN="$(
  ensure_certificate_issued \
    "${CHAT_DOMAIN}" \
    "${ROUTE53_HOSTED_ZONE_ID}" \
    "${ROUTE53_TTL}" \
    "${ACM_MAX_WAIT_SECONDS}" \
    "${ACM_WAIT_INTERVAL_SECONDS}"
)" || exit 1
echo "ACM certificate ready: ${CHAT_CERTIFICATE_ARN}"

#@step "Create or reuse CloudFront distribution for chat.aiemotion.net"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env CHAT_DOMAIN=chat.aiemotion.net
#@env CHAT_BUCKET_NAME=chat-aiemotion-net
. ".playbook/lib/chat.sh"
init_aws_cmd

CHAT_CERTIFICATE_ARN="$(get_certificate_arn_for_domain "${CHAT_DOMAIN}")"
if [ -z "${CHAT_CERTIFICATE_ARN}" ] || [ "${CHAT_CERTIFICATE_ARN}" = "None" ]; then
  echo "ACM certificate not found in ISSUED list for ${CHAT_DOMAIN}. Run certificate step first."
  exit 1
fi

CHAT_OAC_ID="$(ensure_cloudfront_oac "${CHAT_BUCKET_NAME}")"
if [ -z "${CHAT_OAC_ID}" ] || [ "${CHAT_OAC_ID}" = "None" ]; then
  echo "Failed to create or resolve OAC for ${CHAT_BUCKET_NAME}."
  exit 1
fi

CHAT_RESPONSE_HEADERS_POLICY_ID="$(ensure_cloudfront_cors_policy "${CHAT_BUCKET_NAME}")"
if [ -z "${CHAT_RESPONSE_HEADERS_POLICY_ID}" ] || [ "${CHAT_RESPONSE_HEADERS_POLICY_ID}" = "None" ]; then
  echo "Failed to create or resolve response headers policy for ${CHAT_BUCKET_NAME}."
  exit 1
fi

CF_DISTRIBUTION_ID="$(
  ensure_cloudfront_distribution \
    "${CHAT_BUCKET_NAME}" \
    "${CHAT_DOMAIN}" \
    "${CHAT_CERTIFICATE_ARN}" \
    "${CHAT_OAC_ID}" \
    "${CHAT_RESPONSE_HEADERS_POLICY_ID}"
)"
if [ -z "${CF_DISTRIBUTION_ID}" ] || [ "${CF_DISTRIBUTION_ID}" = "None" ]; then
  echo "Failed to create or resolve CloudFront distribution for ${CHAT_DOMAIN}."
  exit 1
fi
reconcile_cloudfront_distribution_config \
  "${CF_DISTRIBUTION_ID}" \
  "${CHAT_BUCKET_NAME}" \
  "${CHAT_DOMAIN}" \
  "${CHAT_CERTIFICATE_ARN}" \
  "${CHAT_OAC_ID}" \
  "${CHAT_RESPONSE_HEADERS_POLICY_ID}" || exit 1
log_ok "CloudFront distribution ready: ${CF_DISTRIBUTION_ID}"

#@step "Ensure S3 bucket policy allows only this CloudFront distribution"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env CHAT_DOMAIN=chat.aiemotion.net
#@env CHAT_BUCKET_NAME=chat-aiemotion-net
. ".playbook/lib/chat.sh"
init_aws_cmd

CF_DISTRIBUTION_ID="$(find_distribution_id_by_alias "${CHAT_DOMAIN}")"
if [ -z "${CF_DISTRIBUTION_ID}" ] || [ "${CF_DISTRIBUTION_ID}" = "None" ]; then
  echo "CloudFront distribution for ${CHAT_DOMAIN} not found."
  exit 1
fi
ensure_s3_policy_for_cloudfront_distribution "${CHAT_BUCKET_NAME}" "${CF_DISTRIBUTION_ID}" || exit 1
log_ok "S3 bucket policy updated for distribution ${CF_DISTRIBUTION_ID}"

#@step "Ensure /usercontent/* CloudFront behavior exists"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env CHAT_DOMAIN=chat.aiemotion.net
#@env CHAT_BUCKET_NAME=chat-aiemotion-net
. ".playbook/lib/chat.sh"
init_aws_cmd

CF_DISTRIBUTION_ID="$(find_distribution_id_by_alias "${CHAT_DOMAIN}")"
if [ -z "${CF_DISTRIBUTION_ID}" ] || [ "${CF_DISTRIBUTION_ID}" = "None" ]; then
  echo "CloudFront distribution for ${CHAT_DOMAIN} not found."
  exit 1
fi
ensure_usercontent_behavior "${CF_DISTRIBUTION_ID}" "${CHAT_BUCKET_NAME}" || exit 1
log_ok "Behavior /usercontent/* ensured for ${CF_DISTRIBUTION_ID}"

#@group "Route53 DNS for chat.aiemotion.net"

#@step "Apply Route53 alias A record to CloudFront"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env ROUTE53_HOSTED_ZONE_ID=Z04463842QPY69QYWA7RY
#@env CHAT_DOMAIN=chat.aiemotion.net
. ".playbook/lib/chat.sh"
init_aws_cmd

CF_DISTRIBUTION_ID="$(find_distribution_id_by_alias "${CHAT_DOMAIN}")"
if [ -z "${CF_DISTRIBUTION_ID}" ] || [ "${CF_DISTRIBUTION_ID}" = "None" ]; then
  echo "CloudFront distribution for ${CHAT_DOMAIN} not found."
  exit 1
fi
CF_DISTRIBUTION_DOMAIN="$(get_cloudfront_domain "${CF_DISTRIBUTION_ID}")"
if [ -z "${CF_DISTRIBUTION_DOMAIN}" ] || [ "${CF_DISTRIBUTION_DOMAIN}" = "None" ]; then
  echo "Unable to resolve CloudFront domain for distribution ${CF_DISTRIBUTION_ID}."
  exit 1
fi

log_info "Using CloudFront domain: ${CF_DISTRIBUTION_DOMAIN}"
upsert_route53_alias_to_cloudfront "${ROUTE53_HOSTED_ZONE_ID}" "${CHAT_DOMAIN}" "${CF_DISTRIBUTION_DOMAIN}" || exit 1

#@step "Verify chat.aiemotion.net resolves to CloudFront"
#@env CHAT_DOMAIN=chat.aiemotion.net
dig +short "${CHAT_DOMAIN}" A

#@group "CloudFront verification via AWS CLI"

#@step "Show additional cache behaviors (must include only /usercontent/*)"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env CHAT_DOMAIN=chat.aiemotion.net
. ".playbook/lib/chat.sh"
init_aws_cmd

CF_DISTRIBUTION_ID="$(find_distribution_id_by_alias "${CHAT_DOMAIN}")"
if [ -z "${CF_DISTRIBUTION_ID}" ] || [ "${CF_DISTRIBUTION_ID}" = "None" ]; then
  echo "CloudFront distribution for ${CHAT_DOMAIN} not found."
  exit 1
fi
show_additional_behaviors "${CF_DISTRIBUTION_ID}"

#@step "Verify only /usercontent/* exists as additional cache behavior"
#@env AWS_PROFILE=s3-cloudfront-admin
#@env AWS_REGION=us-east-1
#@env CHAT_DOMAIN=chat.aiemotion.net
. ".playbook/lib/chat.sh"
init_aws_cmd

CF_DISTRIBUTION_ID="$(find_distribution_id_by_alias "${CHAT_DOMAIN}")"
if [ -z "${CF_DISTRIBUTION_ID}" ] || [ "${CF_DISTRIBUTION_ID}" = "None" ]; then
  echo "CloudFront distribution for ${CHAT_DOMAIN} not found."
  exit 1
fi
verify_usercontent_only_behavior "${CF_DISTRIBUTION_ID}"
