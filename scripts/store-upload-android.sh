#!/usr/bin/env bash
# Uploads to Google Play with fastlane supply (tabcam_store/fastlane/Fastfile):
# the listing in tabcam_store/android/ (title, descriptions, icon, feature
# graphic, phone screenshots), or a signed App Bundle to a testing track.
# Never the production track, never a submission for review.
#
#   bash scripts/store-upload-android.sh metadata
#   bash scripts/store-upload-android.sh upload [aab path | release tag] [track] [draft|completed]
#
# The bundle defaults to make appbundle's
# (tabcam_app/build/app/outputs/bundle/release/app-release.aab); a release
# tag (e.g. 0.2.202610171036-GA) downloads that GitHub release's
# tabcam-<tag>-android.aab, signed with the upload key. The track defaults
# to internal, the status to draft (all Play takes before the app's first
# review).
#
# Needs fastlane (brew install fastlane) and a Google Cloud service account
# with access to the app in Play Console (Users and permissions), its JSON
# key kept outside the repo:
#   PLAY_JSON_KEY_PATH  the service account's JSON key
# Play's API can't create the app: it must exist in Play Console, with its
# first App Bundle uploaded there by hand.
set -euo pipefail

cd "$(dirname "$0")/.."
command -v fastlane >/dev/null || { echo "error: fastlane not found (brew install fastlane)" >&2; exit 1; }
[[ -n "${PLAY_JSON_KEY_PATH:-}" ]] || { echo "error: PLAY_JSON_KEY_PATH isn't set" >&2; exit 1; }
[[ -f "$PLAY_JSON_KEY_PATH" ]] || { echo "error: no key at $PLAY_JSON_KEY_PATH" >&2; exit 1; }
PLAY_JSON_KEY_PATH="$(cd "$(dirname "$PLAY_JSON_KEY_PATH")" && pwd)/$(basename "$PLAY_JSON_KEY_PATH")"
export PLAY_JSON_KEY_PATH

export FASTLANE_SKIP_UPDATE_CHECK=1 FASTLANE_HIDE_CHANGELOG=1 FASTLANE_OPT_OUT_USAGE=1
case "${1:-}" in
  metadata)
    bash scripts/store-metadata-check.sh >/dev/null
    cd tabcam_store && fastlane android metadata
    ;;
  upload)
    src="${2:-tabcam_app/build/app/outputs/bundle/release/app-release.aab}"
    track="${3:-internal}"
    status="${4:-draft}"
    [[ "$track" =~ ^[a-z0-9:_-]+$ && "$track" != production ]] || { echo "error: bad track '$track'" >&2; exit 1; }
    [[ "$status" == draft || "$status" == completed ]] || { echo "error: status is draft or completed" >&2; exit 1; }
    if [[ "$src" =~ ^[0-9]+\.[0-9]+\.[0-9]{12}-(RC|GA)$ ]]; then
      dir="$(mktemp -d)"
      trap 'rm -rf "$dir"' EXIT
      gh release download "$src" --pattern "tabcam-$src-android.aab" --dir "$dir"
      aab="$dir/tabcam-$src-android.aab"
    else
      aab="$src"
    fi
    [[ -f "$aab" ]] || { echo "error: no App Bundle at $aab (make appbundle)" >&2; exit 1; }
    aab="$(cd "$(dirname "$aab")" && pwd)/$(basename "$aab")"
    cd tabcam_store && fastlane android upload "aab:$aab" "track:$track" "status:$status"
    ;;
  *)
    sed -n '2,22p' "$0" >&2
    exit 1
    ;;
esac
