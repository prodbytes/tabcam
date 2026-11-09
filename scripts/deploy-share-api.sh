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
# TabCam's sessions' authorizer reads the discovery document this API
# serves: until it answers (the first deploy), the stack goes up without
# the authorizer and its /tabcam routes, then again with them once the code
# is uploaded.
# NAMED_IAM: the function's and the access role's names are fixed (the
# access role trusts the function's by name). AUTO_EXPAND: Fn::ForEach.
# One API for production and the RC, so tenancy=shared. $1: the sessions'
# authorizer, true or false.
deploy_stack() {
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
      "SessionAuthorizer=$1" \
    --no-fail-on-empty-changeset
}
existing_url="$(aws cloudformation describe-stacks --stack-name tabcam-share-api \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text 2>/dev/null || true)"
sessions_up=false
if [[ "$existing_url" == https://* ]] && curl -sf "$existing_url/session/.well-known/openid-configuration" \
    | grep -q '"jwks_uri"'; then
  sessions_up=true
fi
deploy_stack "$sessions_up"

echo "==> uploading the code"
mkdir "$work/package"
files=(index.py profiles.py keys.py sealed.py apple_revoke.py cdn.py sessions.py adjectives.txt animals.txt)
for f in "${files[@]}"; do cp "tabcam_api/shares/$f" "$work/package/"; done
"$work/venv/bin/pip" install --quiet --only-binary=:all: --require-hashes \
  --platform manylinux_2_28_aarch64 --platform manylinux_2_17_aarch64 \
  --platform manylinux2014_aarch64 --implementation cp --python-version 3.13 \
  --target "$work/package" -r tabcam_api/shares/requirements.txt
(cd "$work/package" && "$work/venv/bin/python" -I -m zipfile -c ../share-api.zip ./*)
aws lambda update-function-code --function-name tabcam-share-api \
  --zip-file "fileb://$work/share-api.zip" --query LastModified --output text
aws lambda wait function-updated --function-name tabcam-share-api
if [[ "$sessions_up" != true ]]; then
  echo "==> adding the sessions' authorizer and /tabcam routes"
  deploy_stack true
fi

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
# TabCam's sessions: the discovery document names this API's issuer, its
# routes want a TabCam token, and an unknown refresh token is refused.
issuer="$(curl -s "$url/session/.well-known/openid-configuration" \
  | python3 -I -c 'import json, sys; print(json.load(sys.stdin).get("issuer", ""))')"
[[ "$issuer" == "$url/session" ]] || { echo "error: the session issuer is '$issuer', not $url/session" >&2; exit 1; }
curl -sf "$url/session/.well-known/jwks.json" | grep -q '"RS256"' \
  || { echo "error: $url/session/.well-known/jwks.json has no RS256 key" >&2; exit 1; }
status="$(curl -s -o /dev/null -w '%{http_code}' "$url/tabcam/shared")"
[[ "$status" == 401 ]] || { echo "error: $url/tabcam/shared answered $status, not 401" >&2; exit 1; }
status="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
  -d '{"refreshToken":"tcs1.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"}' "$url/session/refresh")"
[[ "$status" == 401 ]] || { echo "error: $url/session/refresh answered $status, not 401" >&2; exit 1; }
echo "    sessions: issuer $issuer, its keys published, /tabcam/… wants a token, unknown refresh tokens refused"
# A real TabCam token through the authorizer: made with the session key,
# for a made-up sign-in, at the one route that refuses TabCam tokens before
# touching anything (starting a session takes a provider's: 400). A 401
# means the authorizer can't check TabCam's tokens (the issuer or the keys).
b64url() { python3 -I -c 'import base64, sys; print(base64.urlsafe_b64encode(sys.stdin.buffer.read()).rstrip(b"=").decode())'; }
kid="$(curl -s "$url/session/.well-known/jwks.json" \
  | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["keys"][0]["kid"])')"
now="$(date +%s)"
header="$(printf '{"alg":"RS256","typ":"JWT","kid":"%s"}' "$kid" | b64url)"
payload="$(printf '{"iss":"%s","aud":"tabcam-app","sub":"deploy-check","idp":"https://accounts.google.com","email":"deploy-check@tabcam.nu01.com","email_verified":true,"iat":%d,"exp":%d}' \
  "$url/session" "$now" "$((now + 300))" | b64url)"
printf '%s' "$header.$payload" > "$work/jwt-input"
signature="$(aws kms sign --key-id alias/tabcam-sessions --message "fileb://$work/jwt-input" \
  --message-type RAW --signing-algorithm RSASSA_PKCS1_V1_5_SHA_256 --query Signature --output text \
  | python3 -I -c 'import base64, sys; print(base64.urlsafe_b64encode(base64.b64decode(sys.stdin.read())).rstrip(b"=").decode())')"
# The authorizer fetches the keys the first time: a few tries.
for attempt in 1 2 3 4 5 6; do
  status="$(curl -s -o /dev/null -w '%{http_code}' -X POST \
    -H "authorization: Bearer $header.$payload.$signature" "$url/tabcam/session")"
  [[ "$status" == 400 ]] && break
  sleep 5
done
[[ "$status" == 400 ]] || { echo "error: a TabCam token at $url/tabcam/session got $status, not 400" >&2; exit 1; }
echo "    a TabCam token signed by the session key passes the /tabcam authorizer"
