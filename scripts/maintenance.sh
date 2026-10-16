#!/usr/bin/env bash
# Puts the system in maintenance mode, or takes it out: writes the site's
# /status.json, which every app (web, Android, iOS) checks at start, every
# 2 minutes and on resume. In maintenance mode the apps show only a sorry
# message. Run by an administrator: it needs AWS credentials that may
# write the site's bucket and invalidate its CloudFront distribution.
#
#   bash scripts/maintenance.sh on [message]   maintenance mode, with an
#                                               optional message for users
#   bash scripts/maintenance.sh off            back to normal
#   bash scripts/maintenance.sh status         what the site says now
#
# Settings, from the environment:
#   STAGE        prod (default) or rc
#   AWS_REGION   default us-east-1
# Deploys (scripts/deploy.sh) leave /status.json as it is.
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_REGION="${AWS_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="$AWS_REGION"
STAGE="${STAGE:-prod}"
case "$STAGE" in
  prod) SITE_STACK=tabcam-web; DOMAIN=tabcam.nu01.com ;;
  rc) SITE_STACK=tabcam-rc-web; DOMAIN=rc.tabcam.nu01.com ;;
  *) echo "error: STAGE must be prod or rc (got '$STAGE')" >&2; exit 2 ;;
esac

live_status() {
  curl -fsS --max-time 20 -H 'Cache-Control: no-cache' \
    "https://$DOMAIN/status.json?t=$(date +%s)" 2>/dev/null || echo '(no status file: not in maintenance)'
}

action="${1:-}"
case "$action" in
  status)
    echo "https://$DOMAIN/status.json: $(live_status)"
    exit 0
    ;;
  on) maintenance=true; message="${2:-}" ;;
  off) maintenance=false; message="" ;;
  *)
    echo "usage: bash scripts/maintenance.sh on [message] | off | status" >&2
    exit 2
    ;;
esac

stack_output() { # stack_output <output key>
  aws cloudformation describe-stacks --stack-name "$SITE_STACK" \
    --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
bucket="$(stack_output SiteBucketName)"
distribution="$(stack_output DistributionId)"
if [[ -z "$bucket" || "$bucket" == None || -z "$distribution" || "$distribution" == None ]]; then
  echo "error: $SITE_STACK isn't deployed (no bucket or distribution)" >&2
  exit 1
fi

# json.dumps quotes the message, whatever it holds.
status="$(MAINTENANCE="$maintenance" MESSAGE="$message" python3 -c '
import json, os
body = {"maintenance": os.environ["MAINTENANCE"] == "true"}
if os.environ["MESSAGE"].strip():
    body["message"] = os.environ["MESSAGE"].strip()
print(json.dumps(body, ensure_ascii=False))')"

echo "==> https://$DOMAIN/status.json: $status"
printf '%s\n' "$status" | aws s3 cp - "s3://$bucket/status.json" \
  --cache-control no-cache --content-type "application/json; charset=utf-8" --only-show-errors
invalidation="$(aws cloudfront create-invalidation --distribution-id "$distribution" \
  --paths /status.json --query Invalidation.Id --output text)"
echo "    waiting for invalidation $invalidation"
aws cloudfront wait invalidation-completed --distribution-id "$distribution" --id "$invalidation"

live="$(live_status)"
want="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["maintenance"])' "$status")"
got="$(python3 -c 'import json,sys
try: print(json.loads(sys.argv[1]).get("maintenance") is True)
except ValueError: print(False)' "$live")"
if [[ "$got" != "$want" ]]; then
  echo "error: the site says $live" >&2
  exit 1
fi
if [[ "$maintenance" == true ]]; then
  echo "==> $DOMAIN is in maintenance mode; apps show the sorry message within 2 minutes"
else
  echo "==> $DOMAIN is out of maintenance mode"
fi
