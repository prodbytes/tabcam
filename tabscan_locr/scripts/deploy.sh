#!/usr/bin/env bash
# Builds the cloud OCR image, pushes it to ECR and deploys the tabscan-ocr
# stack. Run by an administrator (it makes IAM roles), from the repo root:
#
#   bash tabscan_locr/scripts/deploy.sh
#
# Needs: docker, the AWS CLI with admin credentials, the stacks
# tabscan-user-data (with EventBridge on) and, for the app's requests,
# tabscan-identity. Settings (environment or .env): GOOGLE_WEB_CLIENT_ID and
# COGNITO_IDENTITY_POOL_ID (both may be empty: page OCR still works, the
# function URL refuses requests), RBACR_TOKEN_SECRET (default
# tabscan/rbacr-token).
set -euo pipefail

cd "$(dirname "$0")/../.."
if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

region="${AWS_REGION:-us-east-1}"
secret_name="${RBACR_TOKEN_SECRET:-tabscan/rbacr-token}"
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

echo "== Stack tabscan-ocr"
aws cloudformation deploy --region "$region" --stack-name tabscan-ocr \
  --template-file tabscan_infra/ocr.yaml --capabilities CAPABILITY_IAM \
  --no-fail-on-empty-changeset \
  --parameter-overrides \
    "ImageUri=$repo@$digest" \
    "GoogleWebClientId=${GOOGLE_WEB_CLIENT_ID:-}" \
    "IdentityPoolId=${COGNITO_IDENTITY_POOL_ID:-}" \
    "RbacrTokenSecretArn=$secret_arn" \
    "Version=$version"

url="$(aws cloudformation describe-stacks --region "$region" --stack-name tabscan-ocr \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)"
echo "Deployed $version. The app's TABSCAN_OCR_URL: $url"
