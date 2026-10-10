#!/usr/bin/env bash
# Deploys the TabScan web app to production, https://tabscan.nu01.com, or
# with STAGE=rc to the release-candidate site, https://rc.tabscan.nu01.com
# (its own stack, tabscan-rc-web):
#   1. builds the Flutter web app for /app/ (make web, WEB_BASE_HREF=/app/)
#   2. deploys the site (CloudFormation tabscan_infra/site.yaml:
#      tabscan-web: certificate, bucket, CloudFront, DNS, and the Route 53
#      health check of /app/version.json with its alarm emails)
#   3. uploads the index page (/) and the web build (/app/), and
#      invalidates the CloudFront cache
#   4. smoke-tests the live site: /app/version.json must report this
#      version, and / must be the index page
#
# Run by .github/workflows/deploy.yml on *GA tags (deploy-rc.yml on *RC*
# tags), or by hand with admin credentials. Settings, from the environment:
#   TAG          the release tag, X.Y.Z-GA: its X.Y must match the version
#                files and its Z becomes the build's Z (default: none, so Z
#                is the current time)
#   STAGE        prod (default) or rc
#   AWS_REGION   default us-east-1 (CloudFront certificates live there)
#   SKIP_BUILD   1 to deploy an existing tabscan_app/build/web
#   HOSTED_ZONE_ID        the Route 53 zone of tabscan.nu01.com (default:
#                the repo's .env, from the private repo)
#   TABSCAN_HEALTH_EMAILS who is emailed when the health check fails or
#                recovers, comma-separated (also from .env). Each must
#                confirm AWS's subscription email.
#   GOOGLE_WEB_CLIENT_ID, COGNITO_IDENTITY_POOL_ID, USER_DATA_BUCKET
#                sign-in and cloud sync, compiled into the build
#                (scripts/dart-defines.sh; environment over .env). Empty
#                builds an app without sign-in. Their stacks
#                (tabscan-identity, tabscan-user-data) are deployed once by
#                an administrator, not here: see tabscan_infra/README.md.
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
    ;;
  rc)
    stack_prefix=tabscan-rc
    DOMAIN=rc.tabscan.nu01.com
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
for name in HOSTED_ZONE_ID TABSCAN_HEALTH_EMAILS; do
  if [[ -z "${!name:-}" && -f .env ]]; then
    printf -v "$name" '%s' "$(sed -n "s/^$name=//p" .env | tail -1)"
  fi
  if [[ -z "${!name:-}" ]]; then
    echo "error: $name isn't set (environment or .env; see .env.example)" >&2
    exit 1
  fi
done
if [[ ! "$HOSTED_ZONE_ID" =~ ^Z[A-Z0-9]+$ ]]; then
  echo "error: HOSTED_ZONE_ID must be a Route 53 zone ID" >&2
  exit 1
fi
if [[ ! "$TABSCAN_HEALTH_EMAILS" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+(,[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+)*$ ]]; then
  echo "error: TABSCAN_HEALTH_EMAILS must be comma-separated emails" >&2
  exit 1
fi
# Emails are people's: logged only as a count.
echo "    health alarm emails: $(tr ',' '\n' <<<"$TABSCAN_HEALTH_EMAILS" | grep -c .)"

# 1. The web app
if [[ "${SKIP_BUILD:-}" != 1 ]]; then
  echo "==> building the web app for /app/"
  WEB_BASE_HREF=/app/ TABSCAN_STAGE="$STAGE" bash scripts/make.sh web
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
echo "==> deploying $SITE_STACK"
# AUTO_EXPAND: the template's Fn::ForEach (AWS::LanguageExtensions).
aws cloudformation deploy --stack-name "$SITE_STACK" \
  --template-file tabscan_infra/site.yaml --capabilities CAPABILITY_AUTO_EXPAND \
  --parameter-overrides "DomainName=$DOMAIN" "HostedZoneId=$HOSTED_ZONE_ID" \
    "HealthNotificationEmails=$TABSCAN_HEALTH_EMAILS" \
  --no-fail-on-empty-changeset
bucket="$(stack_output "$SITE_STACK" SiteBucketName)"
distribution="$(stack_output "$SITE_STACK" DistributionId)"
echo "    bucket: $bucket, distribution: $distribution"

# 3. The content. Flutter's web files aren't content-hashed, so browsers
# revalidate everything (no-cache); CloudFront is invalidated below.
echo "==> uploading"
aws s3 cp tabscan_index/site/index.html "s3://$bucket/index.html" \
  --cache-control no-cache --content-type "text/html; charset=utf-8" --only-show-errors
aws s3 sync tabscan_app/build/web/ "s3://$bucket/app/" --delete --cache-control no-cache --only-show-errors
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
