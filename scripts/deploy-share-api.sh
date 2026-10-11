#!/usr/bin/env bash
# Deploys the share API (sharing captures by email): the tabscan-share-api
# stack (tabscan_infra/share-api.yaml), then the function's code
# (tabscan_api/shares/index.py). Prints the API's URL, the app's
# TABSCANNER_SHARE_API_URL. Run by an administrator (the stack makes IAM
# roles), after tabscan-user-data and tabscan-identity, and again whenever
# the template or the code changes. Settings, from the environment or .env:
#   TABSCANNER_GOOGLE_WEB_CLIENT_ID
#                the web OAuth client (the tokens' audience)
#   TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID
#                optional: the local web builds' client, trusted too
#   TABSCANNER_APPLE_SIGN_IN
#                optional: 1 to take Sign in with Apple's tokens too (for
#                the bundle ID com.nu01.tabscan), under /apple
#   AWS_REGION   default us-east-1
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
if [[ -z "${TABSCANNER_GOOGLE_WEB_CLIENT_ID:-}" && -f .env ]]; then
  TABSCANNER_GOOGLE_WEB_CLIENT_ID="$(sed -n 's/^TABSCANNER_GOOGLE_WEB_CLIENT_ID=//p' .env | tail -1)"
fi
if [[ -z "${TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID:-}" && -f .env ]]; then
  TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID="$(sed -n 's/^TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID=//p' .env | tail -1)"
fi
if [[ -z "${TABSCANNER_APPLE_SIGN_IN:-}" && -f .env ]]; then
  TABSCANNER_APPLE_SIGN_IN="$(sed -n 's/^TABSCANNER_APPLE_SIGN_IN=//p' .env | tail -1)"
fi
apple_client=""
if [[ "${TABSCANNER_APPLE_SIGN_IN:-}" == 1 || "${TABSCANNER_APPLE_SIGN_IN:-}" == true ]]; then
  apple_client=com.nu01.tabscan
fi
# Passed every time: deploy would keep the stack's old origins otherwise.
origins="https://tabscan.nu01.com,https://rc.tabscan.nu01.com,http://localhost:2012,https://local.tabscan.nu01.com:2443"
if [[ ! "${TABSCANNER_GOOGLE_WEB_CLIENT_ID:-}" =~ ^[0-9]+-[0-9a-z]+\.apps\.googleusercontent\.com$ ]]; then
  echo "error: TABSCANNER_GOOGLE_WEB_CLIENT_ID isn't a Google web client ID (environment or .env)" >&2
  exit 1
fi

echo "==> testing the function"
python3 -I -m unittest discover -s tabscan_api/shares

echo "==> deploying tabscan-share-api"
# NAMED_IAM: the function's and the access role's names are fixed (the
# access role trusts the function's by name). AUTO_EXPAND: Fn::ForEach.
aws cloudformation deploy --stack-name tabscan-share-api \
  --template-file tabscan_infra/share-api.yaml \
  --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
  --parameter-overrides "GoogleWebClientId=$TABSCANNER_GOOGLE_WEB_CLIENT_ID" \
    "GoogleLocalWebClientId=${TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID:-}" \
    "AppleClientId=$apple_client" \
    "AllowedOrigins=$origins" \
  --no-fail-on-empty-changeset

echo "==> uploading the code"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp tabscan_api/shares/index.py "$work/"
(cd "$work" && python3 -I -m zipfile -c share-api.zip index.py)
aws lambda update-function-code --function-name tabscan-share-api \
  --zip-file "fileb://$work/share-api.zip" --query LastModified --output text
aws lambda wait function-updated --function-name tabscan-share-api

url="$(aws cloudformation describe-stacks --stack-name tabscan-share-api \
  --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" --output text)"
echo "==> TABSCANNER_SHARE_API_URL=$url"
# Without a token the authorizer answers 401: the API is up.
status="$(curl -s -o /dev/null -w '%{http_code}' "$url/shared")"
[[ "$status" == 401 ]] || { echo "error: $url/shared answered $status, not 401" >&2; exit 1; }
echo "    $url/shared refuses requests without a token (401), as it should"
if [[ -n "$apple_client" ]]; then
  status="$(curl -s -o /dev/null -w '%{http_code}' "$url/apple/shared")"
  [[ "$status" == 401 ]] || { echo "error: $url/apple/shared answered $status, not 401" >&2; exit 1; }
  echo "    $url/apple/shared too (Sign in with Apple)"
fi
