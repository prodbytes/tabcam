#!/usr/bin/env bash
# Deploys the TabScan web app to production, https://tabscan.nu01.com, or
# with STAGE=rc to the release-candidate site, https://rc.tabscan.nu01.com
# (its own stack, tabscan-rc-web):
#   1. builds the Flutter web app for /app/ (make web, WEB_BASE_HREF=/app/)
#   2. deploys the site (CloudFormation tabscan_infra/site.yaml:
#      tabscan-web: certificate, bucket, CloudFront, DNS; uptime is
#      watched by the nu01-monitor stack, outside this repo)
#   3. uploads the index page (/), the privacy policy (/privacy) and the
#      web build (/app/), and invalidates the CloudFront cache
#   4. smoke-tests the live site: /app/version.json must report this
#      version, / must be the index page, and /privacy the policy
#
# Run by .github/workflows/deploy.yml on *GA tags (deploy-rc.yml on *RC*
# tags), or by hand with admin credentials. Settings, from the environment:
#   TAG          the release tag, X.Y.Z-GA: its X.Y must match the version
#                files and its Z becomes the build's Z (default: none, so Z
#                is the current time)
#   STAGE        prod (default) or rc
#   AWS_REGION   default us-east-1 (CloudFront certificates live there)
#   SKIP_BUILD   1 to deploy an existing tabscan_app/build/web
#   TABSCANNER_HOSTED_ZONE_ID
#                the Route 53 zone of tabscan.nu01.com (default: the
#                repo's .env, from the private repo)
#   TABSCANNER_GOOGLE_WEB_CLIENT_ID, TABSCANNER_COGNITO_IDENTITY_POOL_ID,
#   TABSCANNER_USER_DATA_BUCKET, TABSCANNER_SHARE_API_URL
#                sign-in, cloud sync and sharing, compiled into the build
#                (scripts/dart-defines.sh; environment over .env). Empty
#                builds an app without sign-in. Their stacks
#                (tabscan-identity, tabscan-user-data, tabscan-share-api)
#                are deployed by an administrator, not here: see
#                tabscan_infra/README.md.
#   TABSCANNER_OCR_URL
#                TabScan Premium's cloud OCR (tabscan-ocr's ApiUrl,
#                from tabscan_locr/scripts/deploy.sh); empty: no Premium
# Needs the AWS CLI, Python 3 and Flutter (all in devbox).
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
STAGE="${STAGE:-prod}"
case "$STAGE" in
  prod)
    stack_prefix=tabscan
    DOMAIN=tabscan.nu01.com
    tenancy=GA
    ;;
  rc)
    stack_prefix=tabscan-rc
    DOMAIN=rc.tabscan.nu01.com
    tenancy=RC
    ;;
  *) echo "error: STAGE must be prod or rc (got '$STAGE')" >&2; exit 2 ;;
esac
SITE_STACK=$stack_prefix-web

if [[ "${TAG:-}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-.*)?$ ]]; then
  export VERSION_Z="${BASH_REMATCH[3]}"
  tag_xy="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
elif [[ -n "${TAG:-}" ]]; then
  echo "error: TAG '$TAG' isn't X.Y.Z[-suffix]" >&2
  exit 2
fi
# Fixes the build number too, so the build and the check below agree.
export BUILD_NUMBER="${BUILD_NUMBER:-$(date -u +%s)}"
source scripts/version.sh
if [[ -n "${tag_xy:-}" && "$tag_xy" != "$VERSION_X.$VERSION_Y" ]]; then
  echo "error: tag $TAG is version $tag_xy, but version.X.txt/version.Y.txt say $VERSION_X.$VERSION_Y" >&2
  exit 1
fi
echo "==> deploying version $VERSION to https://$DOMAIN/ ($STAGE, $AWS_REGION)"

stack_output() { # stack_output <stack> <output key>
  aws cloudformation describe-stacks --stack-name "$1" \
    --query "Stacks[0].Outputs[?OutputKey=='$2'].OutputValue" --output text
}

# Private settings: from the environment, else the private .env.
for name in TABSCANNER_HOSTED_ZONE_ID; do
  if [[ -z "${!name:-}" && -f .env ]]; then
    printf -v "$name" '%s' "$(sed -n "s/^$name=//p" .env | tail -1)"
  fi
  if [[ -z "${!name:-}" ]]; then
    echo "error: $name isn't set (environment or .env; see .env.example)" >&2
    exit 1
  fi
done
if [[ ! "$TABSCANNER_HOSTED_ZONE_ID" =~ ^Z[A-Z0-9]+$ ]]; then
  echo "error: TABSCANNER_HOSTED_ZONE_ID must be a Route 53 zone ID" >&2
  exit 1
fi

# 1. The web app
if [[ "${SKIP_BUILD:-}" != 1 ]]; then
  echo "==> building the web app for /app/"
  WEB_BASE_HREF=/app/ TABSCANNER_STAGE="$STAGE" bash scripts/make.sh web
fi
# The RC's own title, so its tabs never pass for production's.
if [[ "$STAGE" == rc ]]; then
  python3 - <<'PY'
import json
web = "tabscan_app/build/web"
with open(f"{web}/index.html", encoding="utf-8") as f:
    html = f.read()
html = html.replace("<title>TabScan</title>", "<title>🧪 TabScan RC</title>")
with open(f"{web}/index.html", "w", encoding="utf-8") as f:
    f.write(html)
with open(f"{web}/manifest.json", encoding="utf-8") as f:
    manifest = json.load(f)
manifest["name"] = "🧪 TabScan RC"
manifest["short_name"] = "TabScan RC"
with open(f"{web}/manifest.json", "w", encoding="utf-8") as f:
    json.dump(manifest, f, ensure_ascii=False, indent=4)
PY
  grep -q '<title>🧪 TabScan RC</title>' tabscan_app/build/web/index.html
  echo "    RC title in place"
fi
test -f tabscan_app/build/web/index.html
built="$(python3 -c 'import json; print(json.load(open("tabscan_app/build/web/version.json"))["version"])')"
if [[ "$built" != "$VERSION" ]]; then
  echo "error: tabscan_app/build/web is version $built, not $VERSION" >&2
  exit 1
fi

# 2. The site
# Link previews come from the share API, when the build has one.
share_api_domain="${TABSCANNER_SHARE_API_URL:-}"
share_api_domain="${share_api_domain#https://}"
share_api_domain="${share_api_domain%%/*}"
echo "==> deploying $SITE_STACK"
# The stack's cost-allocation tags reach every resource that takes tags.
aws cloudformation deploy --stack-name "$SITE_STACK" \
  --template-file tabscan_infra/site.yaml \
  --tags project=tabscan "tenancy=$tenancy" \
  --parameter-overrides "DomainName=$DOMAIN" "HostedZoneId=$TABSCANNER_HOSTED_ZONE_ID" \
    "ShareApiDomain=$share_api_domain" \
  --no-fail-on-empty-changeset
bucket="$(stack_output "$SITE_STACK" SiteBucketName)"
distribution="$(stack_output "$SITE_STACK" DistributionId)"
echo "    bucket: $bucket, distribution: $distribution"

# 3. The content. Flutter's web files aren't content-hashed, so browsers
# revalidate everything (no-cache); CloudFront is invalidated below.
echo "==> uploading"
aws s3 cp tabscan_index/site/index.html "s3://$bucket/index.html" \
  --cache-control no-cache --content-type "text/html; charset=utf-8" --only-show-errors
# The privacy policy at /privacy: an object named privacy, served as HTML
# (only /app* rewrites directory URIs; locally it's privacy/index.html).
aws s3 cp tabscan_index/site/privacy/index.html "s3://$bucket/privacy" \
  --cache-control no-cache --content-type "text/html; charset=utf-8" --only-show-errors
aws s3 sync tabscan_app/build/web/ "s3://$bucket/app/" --delete --cache-control no-cache --only-show-errors
# Android App Links: which signing keys' apps may open the site's links.
aws s3 cp tabscan_index/site/.well-known/assetlinks.json "s3://$bucket/.well-known/assetlinks.json" \
  --cache-control no-cache --content-type application/json --only-show-errors
invalidation="$(aws cloudfront create-invalidation --distribution-id "$distribution" \
  --paths '/*' --query Invalidation.Id --output text)"
echo "    waiting for invalidation $invalidation"
aws cloudfront wait invalidation-completed --distribution-id "$distribution" --id "$invalidation"

# 4. Smoke test (retried: on a first deploy DNS and the edge take a moment)
echo "==> checking https://$DOMAIN/"
check() {
  local live
  live="$(curl -fsS --max-time 20 "https://$DOMAIN/app/version.json?deploy=$BUILD_NUMBER" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"])')" || return 1
  [[ "$live" == "$VERSION" ]] || { echo "    /app/version.json says $live, want $VERSION"; return 1; }
  curl -fsS --max-time 20 "https://$DOMAIN/" | grep -q "location.replace('/app/'" || { echo "    / isn't the index page"; return 1; }
  curl -fsS --max-time 20 -o /dev/null "https://$DOMAIN/app/" || { echo "    /app/ failed"; return 1; }
  curl -fsS --max-time 20 "https://$DOMAIN/privacy" | grep -q "<title>TabScan Privacy Policy</title>" || { echo "    /privacy isn't the privacy policy"; return 1; }
}
for attempt in $(seq 1 30); do
  if check; then
    echo "==> https://$DOMAIN/ serves version $VERSION"
    exit 0
  fi
  echo "    not yet (attempt $attempt/30); retrying in 20 s"
  sleep 20
done
echo "error: https://$DOMAIN/ didn't serve version $VERSION" >&2
exit 1
