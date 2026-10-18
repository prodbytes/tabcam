#!/usr/bin/env bash
# App Review for the App Store version, with fastlane
# (tabcam_store/fastlane/Fastfile): takes back the submission waiting for
# review, or submits a version with a processed build (released by hand
# once approved). The listing itself goes up with scripts/store-upload-ios.sh.
#
#   bash scripts/store-submit-ios.sh withdraw
#   bash scripts/store-submit-ios.sh submit <app version> <build number>
#
# To swap the build of a version waiting for review: withdraw, then
# store-upload-ios.sh metadata <new version>, then submit.
#
# Needs fastlane (brew install fastlane) and an App Store Connect API key,
# as scripts/store-upload-ios.sh does: ASC_KEY_ID, ASC_ISSUER_ID,
# ASC_KEY_PATH.
set -euo pipefail

cd "$(dirname "$0")/.."
command -v fastlane >/dev/null || { echo "error: fastlane not found (brew install fastlane)" >&2; exit 1; }
for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
  [[ -n "${!v:-}" ]] || { echo "error: $v isn't set" >&2; exit 1; }
done
[[ -f "$ASC_KEY_PATH" ]] || { echo "error: no key at $ASC_KEY_PATH" >&2; exit 1; }

export FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_HIDE_CHANGELOG=1 FASTLANE_OPT_OUT_USAGE=1
case "${1:-}" in
  withdraw)
    cd tabcam_store && fastlane ios withdraw
    ;;
  submit)
    [[ "${2:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: give the app version (X.Y.Z)" >&2; exit 1; }
    [[ "${3:-}" =~ ^[0-9]+$ ]] || { echo "error: give the build number" >&2; exit 1; }
    cd tabcam_store && fastlane ios submit "app_version:$2" "build:$3"
    ;;
  *)
    sed -n '2,15p' "$0" >&2
    exit 1
    ;;
esac
