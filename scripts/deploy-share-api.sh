#!/usr/bin/env bash
# Deploys the share API (sharing captures by email): the tabcam-share-api
# stack (tabcam_infra/share-api.yaml), then the function's code
# (tabcam_api/shares/index.py). Prints the API's URL, the app's
# TABCAM_SHARE_API_URL. Run by an administrator (the stack makes IAM
# roles), after tabcam-user-data and tabcam-identity, and again whenever
# the template or the code changes. Settings, from the environment or .env:
#   TABCAM_GOOGLE_WEB_CLIENT_ID
#                the web OAuth client (the tokens' audience)
#   TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID
#                optional: the local web builds' client, trusted too
#   TABCAM_APPLE_SIGN_IN
#                optional: 1 to take Sign in with Apple's tokens too (for
#                the bundle ID com.nu01.tabcam, and the Services ID
#                com.nu01.tabcam.signin of the web flow on Android), under
#                /apple
#   APPLE_SIGN_IN_KEY_PARAMETER
#                default /tabcam/apple-sign-in-key: with TABCAM_APPLE_SIGN_IN,
#                the SSM SecureString with the Sign in with Apple key, to
#                revoke a deleted account's Apple tokens (see
#                tabcam_api/shares/apple_revoke.py); may be made later
#   RBACR_TOKEN_PARAMETER
#                default /tabcam/rbacr-token: the SSM SecureString with
#                rbacr's root token (made once, see tabcam_locr/README.md)
#   AWS_REGION   default us-east-1
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
if [[ -z "${TABCAM_GOOGLE_WEB_CLIENT_ID:-}" && -f .env ]]; then
  TABCAM_GOOGLE_WEB_CLIENT_ID="$(sed -n 's/^TABCAM_GOOGLE_WEB_CLIENT_ID=//p' .env | tail -1)"
fi
if [[ -z "${TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID:-}" && -f .env ]]; then
  TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID="$(sed -n 's/^TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID=//p' .env | tail -1)"
fi
if [[ -z "${TABCAM_APPLE_SIGN_IN:-}" && -f .env ]]; then
  TABCAM_APPLE_SIGN_IN="$(sed -n 's/^TABCAM_APPLE_SIGN_IN=//p' .env | tail -1)"
fi
apple_client=""
apple_services=""
if [[ "${TABCAM_APPLE_SIGN_IN:-}" == 1 || "${TABCAM_APPLE_SIGN_IN:-}" == true ]]; then
  apple_client=com.nu01.tabcam
  apple_services=com.nu01.tabcam.signin
fi
# Passed every time: deploy would keep the stack's old origins otherwise.
origins="https://tabcam.nu01.com,https://rc.tabcam.nu01.com,http://localhost:2012,https://local.tabcam.nu01.com:2443"
if [[ ! "${TABCAM_GOOGLE_WEB_CLIENT_ID:-}" =~ ^[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com$ ]]; then
  echo "error: TABCAM_GOOGLE_WEB_CLIENT_ID isn't a Google web client ID (environment or .env)" >&2
  exit 1
fi

# Sign in with email, when tabcam-email-signin is deployed: its tokens'
# issuer and audience (the /email routes).
email_issuer="$(aws cloudformation describe-stacks --stack-name tabcam-email-signin \
  --query "Stacks[0].Outputs[?OutputKey=='Issuer'].OutputValue" --output text 2>/dev/null || true)"
email_client="$(aws cloudformation describe-stacks --stack-name tabcam-email-signin \
  --query "Stacks[0].Outputs[?OutputKey=='ClientId'].OutputValue" --output text 2>/dev/null || true)"
if [[ ! "$email_issuer" =~ ^https://cognito-idp\.[a-z0-9-]+\.amazonaws\.com/[A-Za-z0-9_-]+$ \
      || ! "$email_client" =~ ^[a-z0-9]+$ ]]; then
  email_issuer=""
  email_client=""
fi

# The cloud OCR service's accounts table, when tabcam-ocr is deployed:
# DELETE /account deletes the user's record there too.
accounts="$(aws cloudformation describe-stacks --stack-name tabcam-ocr \
  --query "Stacks[0].Outputs[?OutputKey=='AccountsTable'].OutputValue" \
  --output text 2>/dev/null || true)"
[[ "$accounts" =~ ^[A-Za-z0-9_.-]{3,255}$ && "$accounts" != None ]] || accounts=""

# Profiles' roles come from rbacr, with the token the cloud OCR service uses
# (an SSM SecureString; only its metadata is read here, never its value).
rbacr_param="${RBACR_TOKEN_PARAMETER:-/tabcam/rbacr-token}"
if [[ "$(aws ssm describe-parameters --parameter-filters "Key=Name,Values=$rbacr_param" \
      --query 'Parameters[0].Type' --output text)" != SecureString ]]; then
  echo "error: SSM SecureString $rbacr_param not found (see tabcam_locr/README.md)" >&2
  exit 1
fi

# The Sign in with Apple key (only its metadata is read): without it, deleting
# an Apple account can't revoke its Apple tokens, as App Store review wants.
apple_key_param="${APPLE_SIGN_IN_KEY_PARAMETER:-/tabcam/apple-sign-in-key}"
if [[ -n "$apple_client" && "$(aws ssm describe-parameters --parameter-filters "Key=Name,Values=$apple_key_param" \
      --query 'Parameters[0].Type' --output text)" != SecureString ]]; then
  echo "warning: SSM SecureString $apple_key_param not found: deleting an Apple account won't revoke its Apple tokens until it's made (tabcam_api/shares/apple_revoke.py)" >&2
fi

# CloudFront signed URLs of users' folders (cdn.py): the key's public half,
# from scripts/make-cdn-key.sh (none yet: the app keeps reading S3), and the
# sites' distributions, whose caches a deleted account's folder leaves.
cdn_public_key="$(aws ssm get-parameter --name "${CDN_PUBLIC_KEY_PARAMETER:-/tabcam/cdn-public-key}" \
  --query Parameter.Value --output text 2>/dev/null || true)"
if [[ "$cdn_public_key" != "-----BEGIN PUBLIC KEY-----"* ]]; then
  echo "warning: no CloudFront signing key yet (bash scripts/make-cdn-key.sh): the app reads S3 directly" >&2
  cdn_public_key=""
fi
cdn_distributions=""
for site in tabcam-web tabcam-rc-web; do
  id="$(aws cloudformation describe-stacks --stack-name "$site" \
    --query "Stacks[0].Outputs[?OutputKey=='DistributionId'].OutputValue" --output text 2>/dev/null || true)"
  [[ "$id" =~ ^E[A-Z0-9]+$ ]] && cdn_distributions="${cdn_distributions:+$cdn_distributions,}$id"
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The function's one library beyond boto3, cryptography (keys.py), pinned
# with hashes in requirements.txt: for the tests here, and for the Lambda
# (Python 3.13, arm64) in the package.
echo "==> testing the function"
python3 -m venv "$work/venv"
"$work/venv/bin/pip" install --quiet --only-binary=:all: --require-hashes \
  -r tabcam_api/shares/requirements.txt
"$work/venv/bin/python" -I -m unittest discover -s tabcam_api/shares

echo "==> deploying tabcam-share-api"
# NAMED_IAM: the function's and the access role's names are fixed (the
# access role trusts the function's by name). AUTO_EXPAND: Fn::ForEach.
# One API for production and the RC, so tenancy=shared.
aws cloudformation deploy --stack-name tabcam-share-api \
  --template-file tabcam_infra/share-api.yaml \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --tags project=tabcam tenancy=shared \
  --parameter-overrides "GoogleWebClientId=$TABCAM_GOOGLE_WEB_CLIENT_ID" \
    "GoogleLocalWebClientId=${TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID:-}" \
    "AppleClientId=$apple_client" "AppleServicesId=$apple_services" \
    "EmailIssuer=$email_issuer" "EmailClientId=$email_client" \
    "AllowedOrigins=$origins" \
    "AccountsTableName=$accounts" \
    "RbacrTokenParameterName=$rbacr_param" \
    "AppleSignInKeyParameterName=$apple_key_param" \
    DeveloperProviderName=login.tabcam.profiles \
    "CdnPublicKey=$cdn_public_key" "CdnDistributionIds=$cdn_distributions" \
  --no-fail-on-empty-changeset

echo "==> uploading the code"
mkdir "$work/package"
files=(index.py profiles.py keys.py sealed.py apple_revoke.py cdn.py adjectives.txt animals.txt)
for f in "${files[@]}"; do cp "tabcam_api/shares/$f" "$work/package/"; done
"$work/venv/bin/pip" install --quiet --only-binary=:all: --require-hashes \
  --platform manylinux_2_28_aarch64 --platform manylinux_2_17_aarch64 \
  --platform manylinux2014_aarch64 --implementation cp --python-version 3.13 \
  --target "$work/package" -r tabcam_api/shares/requirements.txt
(cd "$work/package" && "$work/venv/bin/python" -I -m zipfile -c ../share-api.zip ./*)
aws lambda update-function-code --function-name tabcam-share-api \
  --zip-file "fileb://$work/share-api.zip" --query LastModified --output text
aws lambda wait function-updated --function-name tabcam-share-api

url="$(aws cloudformation describe-stacks --stack-name tabcam-share-api \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)"
echo "==> TABCAM_SHARE_API_URL=$url"
key_group="$(aws cloudformation describe-stacks --stack-name tabcam-share-api \
  --query "Stacks[0].Outputs[?OutputKey=='CdnKeyGroupId'].OutputValue" --output text 2>/dev/null || true)"
[[ -n "$key_group" && "$key_group" != None ]] && echo "==> TABCAM_CDN_KEY_GROUP_ID=$key_group"
# Without a token the authorizer answers 401: the API is up.
status="$(curl -s -o /dev/null -w '%{http_code}' "$url/shared")"
[[ "$status" == 401 ]] || { echo "error: $url/shared answered $status, not 401" >&2; exit 1; }
echo "    $url/shared refuses requests without a token (401), as it should"
# The links route takes no token: without a key, the function says 400.
status="$(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{}' "$url/public/abc/credentials")"
[[ "$status" == 400 ]] || { echo "error: $url/public/abc/credentials answered $status, not 400" >&2; exit 1; }
echo "    $url/public/… answers without a token, and wants a link key (400)"
if [[ -n "$apple_client" ]]; then
  status="$(curl -s -o /dev/null -w '%{http_code}' "$url/apple/shared")"
  [[ "$status" == 401 ]] || { echo "error: $url/apple/shared answered $status, not 401" >&2; exit 1; }
  echo "    $url/apple/shared too (Sign in with Apple)"
fi
# The key route wants a sign-in too.
status="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$url/keys/us-east-1:00000000-0000-0000-0000-000000000000/abc")"
[[ "$status" == 401 ]] || { echo "error: $url/keys/… answered $status, not 401" >&2; exit 1; }
echo "    $url/keys/… refuses requests without a token (401), as it should"
