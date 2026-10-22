#!/usr/bin/env bash
# Uploads to Google Play through the Android Publisher API
# (scripts/play_publish.py): the listing in tabcam_store/android/en-US/
# (title, descriptions, icon, feature graphic, phone screenshots), or a
# signed App Bundle to a testing track. Never the production track.
#
#   bash scripts/store-upload-android.sh metadata [--review]
#   bash scripts/store-upload-android.sh upload [aab path | release tag] [track] [draft|completed] [--review]
#
# The bundle defaults to make appbundle's
# (tabcam_app/build/app/outputs/bundle/release/app-release.aab); a release
# tag (e.g. 0.2.202610221407-GA) downloads that GitHub release's
# tabcam-<tag>-android.aab, signed with the upload key. The track defaults
# to internal (the closed test is Alpha), the status to draft. The
# changes are committed without being sent for review, unless --review:
# then Play reviews them (Publishing overview shows them either way).
#
# Keyless: nu01.com's Google Cloud forbids service account keys
# (iam.disableServiceAccountKeyCreation), so the gcloud user signed in
# (julio@nu01.com, with Token Creator on it) gets an hour's token for the
# service account tabcam-play-upload@tabcam-nu01.iam.gserviceaccount.com,
# which Play Console lets release to testing tracks and edit the listing
# (Users and permissions). Needs gcloud, signed in (gcloud auth login).
# Play's API can't create the app: it must exist in Play Console, with its
# first App Bundle uploaded there by hand.
set -euo pipefail

cd "$(dirname "$0")/.."
PLAY_SERVICE_ACCOUNT="${PLAY_SERVICE_ACCOUNT:-tabcam-play-upload@tabcam-nu01.iam.gserviceaccount.com}"
command -v gcloud >/dev/null || { echo "error: gcloud not found" >&2; exit 1; }
token() {
  gcloud auth print-access-token --impersonate-service-account="$PLAY_SERVICE_ACCOUNT" \
    --scopes=https://www.googleapis.com/auth/androidpublisher 2>/dev/null \
    || { echo "error: no token for $PLAY_SERVICE_ACCOUNT (gcloud auth login?)" >&2; exit 1; }
}

review=()
args=()
for a in "$@"; do
  if [[ "$a" == --review ]]; then review=(--review); else args+=("$a"); fi
done
set -- "${args[@]+"${args[@]}"}"

case "${1:-}" in
  metadata)
    bash scripts/store-metadata-check.sh >/dev/null
    PLAY_ACCESS_TOKEN="$(token)" python3 scripts/play_publish.py listing \
      tabcam_store/android/en-US "${review[@]+"${review[@]}"}"
    ;;
  upload)
    src="${2:-tabcam_app/build/app/outputs/bundle/release/app-release.aab}"
    track="${3:-internal}"
    status="${4:-draft}"
    [[ "$track" =~ ^[A-Za-z0-9:_-]+$ && "$track" != production ]] || { echo "error: bad track '$track'" >&2; exit 1; }
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
    PLAY_ACCESS_TOKEN="$(token)" python3 scripts/play_publish.py bundle "$aab" "$track" "$status" \
      --notes tabcam_store/android/en-US/changelogs/default.txt "${review[@]+"${review[@]}"}"
    ;;
  *)
    sed -n '2,25p' "$0" >&2
    exit 1
    ;;
esac
