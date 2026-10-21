#!/usr/bin/env bash
# Measures the cloud OCR's reading in Lambda, on pages already in the
# bucket, with settings to compare; writes no results. Run by an
# administrator, from the repo root, after tabcam-ocr is deployed:
#
#   bash tabcam_locr/scripts/bench.sh <image tag or "build"> <key>...
#
# Settings (environment): BENCH_MEMORY (MB, default 2560), LOCR_MKLDNN (1:
# oneDNN on), LOCR_CPU_THREADS, BENCH_ENV (more variables). Builds and pushes the working tree's image
# with "build". A temporary function, tabcam-ocr-bench, with the ocr
# function's role (it reads pages), is made for the run and deleted after.
set -euo pipefail

cd "$(dirname "$0")/../.."
region="${AWS_REGION:-us-east-1}"
image="${1:?image tag, or build}"
shift
(($#)) || { echo "usage: $0 <tag|build> <key>..." >&2; exit 2; }

repo="$(aws cloudformation describe-stacks --region "$region" --stack-name tabcam-ocr-repo \
  --query "Stacks[0].Outputs[?OutputKey=='RepositoryUri'].OutputValue" --output text)"
if [[ "$image" == build ]]; then
  image="bench-$(git rev-parse --short=12 HEAD)-$(date -u +%Y%m%d%H%M%S)"
  {
    docker build --platform linux/amd64 --provenance=false \
      --build-arg "LOCR_VERSION=$image" -t "$repo:$image" tabcam_locr
    aws ecr get-login-password --region "$region" \
      | docker login --username AWS --password-stdin "${repo%%/*}"
    docker push "$repo:$image"
  } >&2
  echo "Image $image" >&2
fi
[[ "$image" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "bad image tag: $image" >&2; exit 2; }

ocr_function="$(aws cloudformation describe-stack-resources --region "$region" \
  --stack-name tabcam-ocr --logical-resource-id OcrFunction \
  --query "StackResources[0].PhysicalResourceId" --output text)"
role="$(aws lambda get-function-configuration --region "$region" \
  --function-name "$ocr_function" --query Role --output text)"
bucket="$(aws lambda get-function-configuration --region "$region" \
  --function-name "$ocr_function" --query Environment.Variables.USER_DATA_BUCKET --output text)"

name=tabcam-ocr-bench
cleanup() {
  aws lambda delete-function --region "$region" --function-name "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup
env_vars="USER_DATA_BUCKET=$bucket,LOCR_MKLDNN=${LOCR_MKLDNN:-0}"
[[ -n "${LOCR_CPU_THREADS:-}" ]] && env_vars+=",LOCR_CPU_THREADS=$LOCR_CPU_THREADS"
# More variables, KEY=value[,KEY=value] (Paddle's FLAGS_..., say).
[[ -n "${BENCH_ENV:-}" ]] && env_vars+=",$BENCH_ENV"
aws lambda create-function --region "$region" --function-name "$name" \
  --package-type Image --code "ImageUri=$repo:$image" --role "$role" \
  --architectures x86_64 --memory-size "${BENCH_MEMORY:-2560}" --timeout 900 \
  --ephemeral-storage Size=1024 \
  --image-config 'Command=["locr.bench.handler"]' \
  --environment "Variables={$env_vars}" >/dev/null
aws lambda wait function-active-v2 --region "$region" --function-name "$name"

payload="$(python3 -c 'import json, sys; print(json.dumps({"keys": sys.argv[1:]}))' "$@")"
out="$(mktemp)"
aws lambda invoke --region "$region" --function-name "$name" --cli-read-timeout 900 \
  --cli-binary-format raw-in-base64-out --payload "$payload" "$out" >/dev/null
cat "$out"
echo
rm -f "$out"
