#!/usr/bin/env bash
# Makes the key pair the share API signs CloudFront URLs of users' folders
# with (tabcam_api/shares/cdn.py), once: an RSA 2048 key, its private half
# in the SSM SecureString /tabcam/cdn-signing-key (the aws/ssm key), its
# public half in the String /tabcam/cdn-public-key, which
# scripts/deploy-share-api.sh puts in the stack's CloudFront key group.
# With ROTATE=1 it replaces them: deploy the share API right after (the
# signed URLs already handed out stop working, the app asks again).
#
# Needs admin credentials. The private key is only ever in a temporary
# folder (mode 700), deleted on exit, and in SSM.
set -euo pipefail

private_param="${CDN_SIGNING_KEY_PARAMETER:-/tabcam/cdn-signing-key}"
public_param="${CDN_PUBLIC_KEY_PARAMETER:-/tabcam/cdn-public-key}"
region="${AWS_REGION:-us-east-1}"

if aws ssm get-parameter --region "$region" --name "$public_param" >/dev/null 2>&1 \
    && [[ "${ROTATE:-}" != 1 ]]; then
  echo "$public_param already exists: nothing to do (ROTATE=1 replaces the key)"
  exit 0
fi

work="$(mktemp -d)"
chmod 700 "$work"
trap 'rm -rf "$work"' EXIT
umask 077
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$work/private.pem" 2>/dev/null
openssl pkey -in "$work/private.pem" -pubout -out "$work/public.pem"

aws ssm put-parameter --region "$region" --name "$private_param" --type SecureString \
  --overwrite --value "file://$work/private.pem" \
  --description "TabCam: signs CloudFront URLs of users' folders (tabcam_api/shares/cdn.py)" \
  --query Version --output text >/dev/null
aws ssm put-parameter --region "$region" --name "$public_param" --type String \
  --overwrite --value "file://$work/public.pem" \
  --description "TabCam: the public half of $private_param, for CloudFront's key group" \
  --query Version --output text >/dev/null
echo "==> $private_param and $public_param written; now: bash scripts/deploy-share-api.sh"
