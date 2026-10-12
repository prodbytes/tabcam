#!/usr/bin/env bash
# Builds the cloud OCR image, pushes it to ECR and deploys the tabscan-ocr
# stack. Run by an administrator (it makes IAM roles), from the repo root:
#
#   bash tabscan_locr/scripts/deploy.sh
#
# Needs: docker, the AWS CLI with admin credentials, the stacks
# tabscan-user-data (with EventBridge on) and, for the app's requests,
# tabscan-identity. Settings (environment or .env): TABSCANNER_GOOGLE_WEB_CLIENT_ID and
# TABSCANNER_COGNITO_IDENTITY_POOL_ID (both may be empty: page OCR still works, the
# function URL refuses requests), TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID (optional:
# local web builds' client, trusted too), TABSCANNER_APPLE_SIGN_IN (optional:
# 1 to take Sign in with Apple's tokens for the bundle ID too),
# RBACR_TOKEN_SECRET (default tabscan/rbacr-token), ANTHROPIC_KEY_SECRET
# (default tabscan/anthropic-api-key, read by name: auto-correct and Claude
# reading the pages the engines can't are off until it exists, then on).
set -euo pipefail

cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

region="${AWS_REGION:-us-east-1}"
# Passed every time: deploy would keep the stack's old origins otherwise.
TABSCANNER_WEB_ORIGINS="https://tabscan.nu01.com,https://rc.tabscan.nu01.com,http://localhost:2012,https://local.tabscan.nu01.com:2443"
secret_name="${RBACR_TOKEN_SECRET:-tabscan/rbacr-token}"
apple_client=""
if [[ "${TABSCANNER_APPLE_SIGN_IN:-}" == 1 || "${TABSCANNER_APPLE_SIGN_IN:-}" == true ]]; then
  apple_client=com.nu01.tabscan
fi
version="$(git rev-parse --short=12 HEAD)$(git diff --quiet HEAD -- tabscan_locr || echo -dirty)"
tag="${version}-$(date -u +%Y%m%d%H%M%S)"

echo "== ECR repository (tabscan-ocr-repo)"
aws cloudformation deploy --region "$region" --stack-name tabscan-ocr-repo \
  --template-file tabscan_infra/ocr-repo.yaml --no-fail-on-empty-changeset
repo="$(aws cloudformation describe-stacks --region "$region" --stack-name tabscan-ocr-repo \
  --query "Stacks[0].Outputs[?OutputKey=='RepositoryUri'].OutputValue" --output text)"

echo "== Image $repo:$tag"
docker build --platform linux/amd64 --provenance=false \
  --build-arg "LOCR_VERSION=$version" -t "$repo:$tag" tabscan_locr
aws ecr get-login-password --region "$region" \
  | docker login --username AWS --password-stdin "${repo%%/*}"
docker push "$repo:$tag"
digest="$(aws ecr describe-images --region "$region" --repository-name tabscan-ocr \
  --image-ids "imageTag=$tag" --query 'imageDetails[0].imageDigest' --output text)"

secret_arn="$(aws secretsmanager describe-secret --region "$region" --secret-id "$secret_name" \
  --query ARN --output text)"
# The share API's profiles, when it's deployed: folders and addresses by
# profile.
share_output() {
  aws cloudformation describe-stacks --region "$region" --stack-name tabscan-share-api \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null || true
}
profiles_table="$(share_output ProfilesTable)"; subjects_table="$(share_output SubjectsTable)"
[[ "$profiles_table" =~ ^[A-Za-z0-9_.-]{3,255}$ && "$profiles_table" != None ]] || profiles_table=""
[[ "$subjects_table" =~ ^[A-Za-z0-9_.-]{3,255}$ && "$subjects_table" != None ]] || subjects_table=""

echo "== Stack tabscan-ocr"
aws cloudformation deploy --region "$region" --stack-name tabscan-ocr \
  --template-file tabscan_infra/ocr.yaml --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    "ImageUri=$repo@$digest" \
    "GoogleWebClientId=${TABSCANNER_GOOGLE_WEB_CLIENT_ID:-}" \
    "GoogleLocalWebClientId=${TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID:-}" \
    "AppleClientId=$apple_client" \
    "AllowedOrigins=$TABSCANNER_WEB_ORIGINS" \
    "IdentityPoolId=${TABSCANNER_COGNITO_IDENTITY_POOL_ID:-}" \
    "RbacrTokenSecretArn=$secret_arn" \
    "AnthropicKeySecretName=${ANTHROPIC_KEY_SECRET:-tabscan/anthropic-api-key}" \
    "ProfilesTableName=$profiles_table" \
    "SubjectsTableName=$subjects_table" \
    "Version=$version"

url="$(aws cloudformation describe-stacks --region "$region" --stack-name tabscan-ocr \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)"
echo "Deployed $version. The app's TABSCANNER_OCR_URL: $url"
