#!/usr/bin/env bash
# Uploads the App Store listing in tabcam_store/ios/ to App Store Connect
# with fastlane deliver (tabcam_store/fastlane/Fastfile): the metadata
# (tabcam_store/ios/metadata), the screenshots (tabcam_store/ios/screenshots:
# 1320 x 2868 for the 6.9" iPhone, 2064 x 2752 for the 13" iPad), the
# categories (Music, Productivity), the copyright and the age rating
# (tabcam_store/ios/age-rating.json). No binary, no submission for review.
# Or puts a processed build on TestFlight for the internal group.
#
#   bash scripts/store-upload-ios.sh metadata [app version]
#   bash scripts/store-upload-ios.sh testflight <build number> [tester emails, comma-separated]
#
# Needs fastlane (brew install fastlane) and an App Store Connect API key
# (Users and Access > Integrations; App Manager or Admin), as for
# scripts/ios-upload.sh, kept outside the repo:
#   ASC_KEY_ID      the key's ID
#   ASC_ISSUER_ID   the issuer ID
#   ASC_KEY_PATH    the AuthKey_<ID>.p8 file
set -euo pipefail

cd "$(dirname "$0")/.."
command -v fastlane >/dev/null || { echo "error: fastlane not found (brew install fastlane)" >&2; exit 1; }
for v in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_PATH; do
  [[ -n "${!v:-}" ]] || { echo "error: $v isn't set" >&2; exit 1; }
done
[[ -f "$ASC_KEY_PATH" ]] || { echo "error: no key at $ASC_KEY_PATH" >&2; exit 1; }

export FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_HIDE_CHANGELOG=1 FASTLANE_OPT_OUT_USAGE=1
case "${1:-}" in
  metadata)
    bash scripts/store-metadata-check.sh >/dev/null
    args=()
    [[ -n "${2:-}" ]] && args=("app_version:$2")
    cd tabcam_store && fastlane ios metadata ${args[@]+"${args[@]}"}
    ;;
  testflight)
    [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "error: give the build number" >&2; exit 1; }
    args=("build:$2")
    [[ -n "${3:-}" ]] && args+=("testers:$3")
    cd tabcam_store && fastlane ios testflight_internal "${args[@]}"
    ;;
  *)
    sed -n '2,20p' "$0" >&2
    exit 1
    ;;
esac
