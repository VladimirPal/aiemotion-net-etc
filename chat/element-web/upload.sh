#!/bin/bash
set -e

S3_BUCKET="chat-aiemotion-net"
S3_REGION="eu-east-1"
DISTRIBUTION_ID="E2GRJ0JIBI4UJX"
AWS_PROFILE="chat.aiemotion.net"
export AWS_SHARED_CREDENTIALS_FILE=/etc/chat/element-web/.aws-credentials
export AWS_PROFILE
export S3_REGION

DIST_DIR="/etc/chat/element-web/repo/webapp"

cd "$DIST_DIR"

echo "Uploading to S3..."
aws s3 sync . s3://$S3_BUCKET --profile $AWS_PROFILE

echo "Invalidating CloudFront cache..."
aws cloudfront create-invalidation --distribution-id $DISTRIBUTION_ID --paths "/*" >/dev/null

echo "Deployment complete. Visit https://$AWS_PROFILE to see changes."
