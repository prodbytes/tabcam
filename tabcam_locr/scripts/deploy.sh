#!/usr/bin/env bash
# Builds the cloud OCR image, pushes it to ECR and deploys the tabcam-ocr
# stack. Run by an administrator (it makes IAM roles), from the repo root:
#
#   bash tabcam_locr/scripts/deploy.sh
#
# Needs: docker, the AWS CLI with admin credentials, the stacks
# tabcam-user-data (with EventBridge on) and, for the app's requests,
# tabcam-identity. Settings (environment or .env): TABCAM_GOOGLE_WEB_CLIENT_ID and
# TABCAM_COGNITO_IDENTITY_POOL_ID (both may be empty: page OCR still works, the
# function URL refuses requests), TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID (optional:
# local web builds' client, trusted too), TABCAM_APPLE_SIGN_IN (optional:
# 1 to take Sign in with Apple's tokens for the bundle ID too),
# RBACR_TOKEN_PARAMETER (default /tabcam/rbacr-token, an SSM SecureString),
# ANTHROPIC_KEY_SECRET
# (default tabcam/anthropic-api-key, read by name: auto-correct and Claude
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
TABCAM_WEB_ORIGINS="https://tabcam.nu01.com,https://rc.tabcam.nu01.com,http://localhost:2012,https://local.tabcam.nu01.com:2443"
rbacr_param="${RBACR_TOKEN_PARAMETER:-/tabcam/rbacr-token}"
# Sign in with email, when tabcam-email-signin is deployed: its tokens'
# issuer and audience.
email_issuer="$(aws cloudformation describe-stacks --region "$region" --stack-name tabcam-email-signin \
  --query "Stacks[0].Outputs[?OutputKey=='Issuer'].OutputValue" --output text 2>/dev/null || true)"
email_client="$(aws cloudformation describe-stacks --region "$region" --stack-name tabcam-email-signin \
  --query "Stacks[0].Outputs[?OutputKey=='ClientId'].OutputValue" --output text 2>/dev/null || true)"
if [[ ! "$email_issuer" =~ ^https://cognito-idp\.[a-z0-9-]+\.amazonaws\.com/[A-Za-z0-9_-]+$ \
      || ! "$email_client" =~ ^[a-z0-9]+$ ]]; then
  email_issuer=""
  email_client=""
fi
apple_client=""
if [[ "${TABCAM_APPLE_SIGN_IN:-}" == 1 || "${TABCAM_APPLE_SIGN_IN:-}" == true ]]; then
  # The bundle ID (iOS) and the Services ID (the web flow, on Android).
  apple_client=com.nu01.tabcam,com.nu01.tabcam.signin
fi
version="$(git rev-parse --short=12 HEAD)$(git diff --quiet HEAD -- tabcam_locr || echo -dirty)"
tag="${version}-$(date -u +%Y%m%d%H%M%S)"

# One OCR service for production and the RC: cost-allocation tags
# tenancy=shared.
tags=(project=tabcam tenancy=shared)

# The rbacr token, checked before building: only its metadata is read,
# never its value.
if [[ "$(aws ssm describe-parameters --region "$region" \
      --parameter-filters "Key=Name,Values=$rbacr_param" \
      --query 'Parameters[0].Type' --output text)" != SecureString ]]; then
  echo "error: SSM SecureString $rbacr_param not found (see tabcam_locr/README.md)" >&2
  exit 1
fi

echo "== ECR repository (tabcam-ocr-repo)"
aws cloudformation deploy --region "$region" --stack-name tabcam-ocr-repo \
  --template-file tabcam_infra/ocr-repo.yaml --tags "${tags[@]}" --no-fail-on-empty-changeset
repo="$(aws cloudformation describe-stacks --region "$region" --stack-name tabcam-ocr-repo \
  --query "Stacks[0].Outputs[?OutputKey=='RepositoryUri'].OutputValue" --output text)"

echo "== Image $repo:$tag"
docker build --platform linux/amd64 --provenance=false \
  --build-arg "LOCR_VERSION=$version" -t "$repo:$tag" tabcam_locr
aws ecr get-login-password --region "$region" \
  | docker login --username AWS --password-stdin "${repo%%/*}"
docker push "$repo:$tag"
digest="$(aws ecr describe-images --region "$region" --repository-name tabcam-ocr \
  --image-ids "imageTag=$tag" --query 'imageDetails[0].imageDigest' --output text)"

# The share API's profiles, when it's deployed: folders and addresses by
# profile.
share_output() {
  aws cloudformation describe-stacks --region "$region" --stack-name tabcam-share-api \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text 2>/dev/null || true
}
profiles_table="$(share_output ProfilesTable)"; subjects_table="$(share_output SubjectsTable)"
[[ "$profiles_table" =~ ^[A-Za-z0-9_.-]{3,255}$ && "$profiles_table" != None ]] || profiles_table=""
[[ "$subjects_table" =~ ^[A-Za-z0-9_.-]{3,255}$ && "$subjects_table" != None ]] || subjects_table=""

echo "== Stack tabcam-ocr"
aws cloudformation deploy --region "$region" --stack-name tabcam-ocr \
  --template-file tabcam_infra/ocr.yaml --capabilities CAPABILITY_IAM \
  --tags "${tags[@]}" --no-fail-on-empty-changeset \
  --parameter-overrides \
    "ImageUri=$repo@$digest" \
    "GoogleWebClientId=${TABCAM_GOOGLE_WEB_CLIENT_ID:-}" \
    "GoogleLocalWebClientId=${TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID:-}" \
    "AppleClientId=$apple_client" \
    "EmailIssuer=$email_issuer" "EmailClientId=$email_client" \
    "AllowedOrigins=$TABCAM_WEB_ORIGINS" \
    "IdentityPoolId=${TABCAM_COGNITO_IDENTITY_POOL_ID:-}" \
    "RbacrTokenParameterName=$rbacr_param" \
    "AnthropicKeySecretName=${ANTHROPIC_KEY_SECRET:-tabcam/anthropic-api-key}" \
    "ProfilesTableName=$profiles_table" \
    "SubjectsTableName=$subjects_table" \
    "Version=$version"

url="$(aws cloudformation describe-stacks --region "$region" --stack-name tabcam-ocr \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)"
echo "Deployed $version. The app's TABCAM_OCR_URL: $url"

# A new image's first page waits for Lambda to fetch it and load the
# models (80-120 s more, measured): one warm-up now takes that wait.
ocr_function="$(aws cloudformation describe-stack-resources --region "$region" \
  --stack-name tabcam-ocr --logical-resource-id OcrFunction \
  --query "StackResources[0].PhysicalResourceId" --output text)"
warm_out="$(mktemp)"
if aws lambda invoke --region "$region" --function-name "$ocr_function" \
    --cli-read-timeout 300 --payload '{"warm": true}' \
    --cli-binary-format raw-in-base64-out "$warm_out" >/dev/null; then
  echo "Warmed $ocr_function: $(cat "$warm_out")"
else
  echo "Warming $ocr_function failed (the first page will be slower)" >&2
fi
rm -f "$warm_out"
