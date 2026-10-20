#!/usr/bin/env bash
# Retires everything left of TabScan (renamed TabCam on 2026-10-16) in AWS
# and GitHub, and recreates under tabcam names the two things still needed:
#
#   - the accounts.google.com IAM OIDC provider, which tabscan-identity owns
#     and tabcam-identity / tabcam-identity-local use: kept (Retain), then
#     imported into tabcam-identity, trusting TabCam's Google clients only;
#   - the redirects tabscan.nu01.com -> tabcam.nu01.com and
#     rc.tabscan.nu01.com -> rc.tabcam.nu01.com (links shared before the
#     rename): stacks tabcam-old-domain and tabcam-rc-old-domain
#     (tabcam_infra/site.yaml with RedirectTo), made after the old ones go.
#
# DELETES FOR GOOD: the tabscan-* stacks and what's in them (the old user
# data bucket nu01-user-events-<account> with every version, the old share
# API's DynamoDB tables, the old OCR accounts table, the tabscan and
# tabscan-local Cognito identity pools, the old OCR images, the old site
# buckets), the profile KMS key (scheduled, 7 days), the tabscan secret and
# SSM parameter, leftover log groups, local.tabscan.nu01.com's records and
# the repository's old TABSCANNER_* / AWS_DEPLOY_* variables. Everything in
# use moved to the tabcam-* stacks on 2026-10-16
# (scripts/migrate-to-tabcam.py). The old domains don't answer between the
# old redirect stacks going and the new ones being up (CloudFront takes
# ~15 minutes).
#
# Run by an administrator, from the repo root, with the AWS CLI (admin) and
# gh (repository admin):
#
#   bash scripts/retire-tabscan.sh
#
# It asks before deleting. Steps already done are skipped, so it can run
# again after a failure.
set -euo pipefail
cd "$(dirname "$0")/.."

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGION="${AWS_REGION:-us-east-1}"
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION"
PROVIDER_ARN="arn:aws:iam::${ACCOUNT}:oidc-provider/accounts.google.com"
OLD_ZONE=Z10277161AEN9OU2H73PJ   # tabscan.nu01.com
OLD_BUCKET="nu01-user-events-${ACCOUNT}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

say() { printf '\n==> %s\n' "$*"; }
exists() { aws cloudformation describe-stacks --stack-name "$1" >/dev/null 2>&1; }

delete_stack() {
  exists "$1" || { echo "    $1: gone already"; return; }
  echo "    deleting $1"
  aws cloudformation delete-stack --stack-name "$1"
  aws cloudformation wait stack-delete-complete --stack-name "$1"
}

# Every object version and delete marker in [bucket], 1000 at a time.
empty_bucket() {
  local bucket="$1" batch
  aws s3api head-bucket --bucket "$bucket" 2>/dev/null || return 0
  echo "    emptying $bucket"
  while :; do
    batch="$(aws s3api list-object-versions --bucket "$bucket" --max-items 1000 --output json \
      --query '{Objects: [Versions[].{Key: Key, VersionId: VersionId}, DeleteMarkers[].{Key: Key, VersionId: VersionId}][]}')"
    [[ "$(jq '.Objects | length' <<<"$batch")" == 0 ]] && break
    jq '{Objects: .Objects[:1000], Quiet: true}' <<<"$batch" > "$WORK/batch.json"
    aws s3api delete-objects --bucket "$bucket" --delete "file://$WORK/batch.json" >/dev/null
  done
}

stack_bucket() {
  aws cloudformation list-stack-resources --stack-name "$1" \
    --query "StackResourceSummaries[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" \
    --output text 2>/dev/null || true
}

cat <<EOF
This deletes every tabscan-* stack in account $ACCOUNT ($REGION) and all
their data (the old user data bucket $OLD_BUCKET among them), the old
GitHub variables, and recreates the old domains' redirects as tabcam-*
stacks. It can't be undone.
EOF
read -r -p "Type 'retire tabscan' to go on: " answer
[[ "$answer" == "retire tabscan" ]] || { echo "Nothing done."; exit 1; }

say "1. Keep the Google sign-in provider when tabscan-identity goes"
if exists tabscan-identity; then
  aws cloudformation get-template --stack-name tabscan-identity \
    --query TemplateBody --output text > "$WORK/tabscan-identity.yaml"
  if ! grep -q "DeletionPolicy: Retain" "$WORK/tabscan-identity.yaml"; then
    python3 - "$WORK/tabscan-identity.yaml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "  GoogleProvider:\n    Type: AWS::IAM::OIDCProvider\n"
assert s.count(old) == 1, "GoogleProvider not found once"
open(p, "w").write(s.replace(old, old + "    DeletionPolicy: Retain\n    UpdateReplacePolicy: Retain\n"))
PY
    params=$(aws cloudformation describe-stacks --stack-name tabscan-identity \
      --query 'Stacks[0].Parameters[].ParameterKey' --output text | tr '\t' '\n' \
      | sed 's/.*/ParameterKey=&,UsePreviousValue=true/')
    # shellcheck disable=SC2086
    aws cloudformation update-stack --stack-name tabscan-identity \
      --template-body "file://$WORK/tabscan-identity.yaml" --parameters $params \
      --capabilities CAPABILITY_IAM >/dev/null
    aws cloudformation wait stack-update-complete --stack-name tabscan-identity
  fi
  echo "    the provider stays when the stack goes"
fi

say "2. The old domains' redirect stacks"
for s in tabscan-web tabscan-rc-web; do
  exists "$s" && for b in $(stack_bucket "$s"); do empty_bucket "$b"; done
  delete_stack "$s"
done

say "3. The old OCR, share API and identity pools"
delete_stack tabscan-ocr
key="$(aws kms describe-key --key-id alias/tabscan-profile-keys --query KeyMetadata.KeyId --output text 2>/dev/null || true)"
delete_stack tabscan-share-api
delete_stack tabscan-identity-local
delete_stack tabscan-identity
if [[ -n "$key" && "$key" != None ]]; then
  state="$(aws kms describe-key --key-id "$key" --query KeyMetadata.KeyState --output text)"
  if [[ "$state" != PendingDeletion ]]; then
    aws kms schedule-key-deletion --key-id "$key" --pending-window-in-days 7 >/dev/null
    echo "    KMS key $key: deleted in 7 days"
  fi
  aws kms delete-alias --alias-name alias/tabscan-profile-keys 2>/dev/null || true
fi

say "4. The old OCR images"
if aws ecr describe-repositories --repository-names tabscan-ocr >/dev/null 2>&1; then
  ids="$(aws ecr list-images --repository-name tabscan-ocr --query 'imageIds[*]' --output json)"
  [[ "$ids" != "[]" ]] && aws ecr batch-delete-image --repository-name tabscan-ocr \
    --image-ids "$ids" >/dev/null
fi
delete_stack tabscan-ocr-repo

say "5. The old user data bucket"
empty_bucket "$OLD_BUCKET"
delete_stack tabscan-user-data

say "6. The old deploy roles"
delete_stack tabscan-github-deploy

say "7. Leftovers outside the stacks"
aws secretsmanager delete-secret --secret-id tabscan/rbacr-token \
  --force-delete-without-recovery >/dev/null 2>&1 && echo "    secret tabscan/rbacr-token" || true
aws ssm delete-parameter --name /tabscan/rbacr-token 2>/dev/null && echo "    parameter /tabscan/rbacr-token" || true
for g in $(aws logs describe-log-groups --log-group-name-prefix /aws/lambda/tabscan \
    --query 'logGroups[].logGroupName' --output text); do
  aws logs delete-log-group --log-group-name "$g" && echo "    log group $g"
done
changes="$(aws route53 list-resource-record-sets --hosted-zone-id "$OLD_ZONE" --output json \
  | jq '[.ResourceRecordSets[] | select(.Name == "local.tabscan.nu01.com.") | {Action: "DELETE", ResourceRecordSet: .}]')"
if [[ "$changes" != "[]" ]]; then
  jq -n --argjson c "$changes" '{Changes: $c}' > "$WORK/records.json"
  aws route53 change-resource-record-sets --hosted-zone-id "$OLD_ZONE" \
    --change-batch "file://$WORK/records.json" >/dev/null && echo "    local.tabscan.nu01.com"
fi
for v in AWS_DEPLOY_ROLE_ARN AWS_DEPLOY_RC_ROLE_ARN TABSCANNER_AWS_DEPLOY_ROLE_ARN \
    TABSCANNER_AWS_DEPLOY_RC_ROLE_ARN TABSCANNER_COGNITO_IDENTITY_POOL_ID \
    TABSCANNER_GOOGLE_IOS_CLIENT_ID TABSCANNER_GOOGLE_WEB_CLIENT_ID \
    TABSCANNER_HOSTED_ZONE_ID TABSCANNER_OCR_URL TABSCANNER_SHARE_API_URL \
    TABSCANNER_USER_DATA_BUCKET; do
  gh variable delete "$v" >/dev/null 2>&1 && echo "    GitHub variable $v" || true
done

say "8. The Google sign-in provider, into tabcam-identity"
owner="$(aws cloudformation describe-stack-resources --physical-resource-id "$PROVIDER_ARN" \
  --query 'StackResources[0].StackName' --output text 2>/dev/null || true)"
if [[ "$owner" != tabcam-identity ]]; then
  # The import: the deployed template plus the provider, unconditional and
  # with the provider's current clients, nothing else changed.
  aws cloudformation get-template --stack-name tabcam-identity \
    --query TemplateBody --output text > "$WORK/import.yaml"
  aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" \
    --query ClientIDList --output json > "$WORK/clients.json"
  python3 - "$WORK/import.yaml" "$WORK/clients.json" <<'PY'
import json, sys
p, clients = sys.argv[1], json.load(open(sys.argv[2]))
s = open(p).read()
start = s.index("  GoogleProvider:\n")
end = s.index("\n\n", start)
block = ("  GoogleProvider:\n    Type: AWS::IAM::OIDCProvider\n"
         "    DeletionPolicy: Retain\n    UpdateReplacePolicy: Retain\n"
         "    Properties:\n      Url: https://accounts.google.com\n      ClientIdList:\n"
         + "".join(f"        - {c}\n" for c in clients).rstrip("\n"))
open(p, "w").write(s[:start] + block + s[end:])
PY
  printf '[{"ResourceType":"AWS::IAM::OIDCProvider","LogicalResourceId":"GoogleProvider","ResourceIdentifier":{"Arn":"%s"}}]' \
    "$PROVIDER_ARN" > "$WORK/import.json"
  params=$(aws cloudformation describe-stacks --stack-name tabcam-identity \
    --query 'Stacks[0].Parameters[].ParameterKey' --output text | tr '\t' '\n' \
    | sed 's/.*/ParameterKey=&,UsePreviousValue=true/')
  # shellcheck disable=SC2086
  aws cloudformation create-change-set --stack-name tabcam-identity \
    --change-set-name import-google-provider --change-set-type IMPORT \
    --resources-to-import "file://$WORK/import.json" \
    --template-body "file://$WORK/import.yaml" --parameters $params \
    --capabilities CAPABILITY_IAM >/dev/null
  aws cloudformation wait change-set-create-complete --stack-name tabcam-identity \
    --change-set-name import-google-provider
  aws cloudformation execute-change-set --stack-name tabcam-identity \
    --change-set-name import-google-provider
  aws cloudformation wait stack-import-complete --stack-name tabcam-identity
  echo "    imported"
  # Then the repo's template, making it (GoogleProviderArn empty), with the
  # provider's clients as they are. Not the stack's own Google parameters:
  # on 2026-10-19 they were still TabScan's, and deploying them replaced
  # TabCam's clients with TabScan's (Google sign-in failed everywhere until
  # they were put back). The clients change only by deploying identity.yaml
  # with TabCam's IDs (tabcam_infra/README.md).
  web="${TABCAM_GOOGLE_WEB_CLIENT_ID:-$(sed -n 's/^TABCAM_GOOGLE_WEB_CLIENT_ID=//p' .env | tail -1)}"
  apps="$(python3 -c 'import json,sys; print(",".join(c for c in json.load(open(sys.argv[1])) if c != sys.argv[2]))' \
    "$WORK/clients.json" "$web")"
  aws cloudformation deploy --stack-name tabcam-identity \
    --template-file tabcam_infra/identity.yaml --capabilities CAPABILITY_IAM \
    --no-fail-on-empty-changeset \
    --parameter-overrides GoogleProviderArn= "GoogleWebClientId=$web" "GoogleAppClientIds=$apps"
fi
echo "    clients: $(aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" \
  --query 'length(ClientIDList)' --output text)"

say "9. The old domains' redirects, as tabcam stacks"
for pair in "tabcam-old-domain tabscan.nu01.com tabcam.nu01.com" \
            "tabcam-rc-old-domain rc.tabscan.nu01.com rc.tabcam.nu01.com"; do
  read -r stack domain target <<<"$pair"
  aws cloudformation deploy --stack-name "$stack" \
    --template-file tabcam_infra/site.yaml --no-fail-on-empty-changeset \
    --tags project=tabcam "tenancy=$([[ $stack == *rc* ]] && echo RC || echo GA)" \
    --parameter-overrides "DomainName=$domain" "HostedZoneId=$OLD_ZONE" "RedirectTo=$target"
  printf '    %s -> %s: ' "$domain" "$target"
  curl -s -o /dev/null -w '%{http_code} %{redirect_url}\n' "https://$domain/app/?c=x" || echo "not up yet"
done

say "Done. Left as they are: the tabscan.nu01.com zone (the redirects need it),"
echo "    rbacr's tabscan system (until Presence's vouchers name tabcam), and"
echo "    nu01-dns's unused Tabscan* parameters."
