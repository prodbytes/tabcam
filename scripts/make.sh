#!/usr/bin/env bash
# Builds the app binaries. Run through the Makefile (`make`, `make web`, ...)
# or directly: `bash scripts/make.sh <target>...`.
#
# Targets: web, android (APK), appbundle (Android App Bundle, for Google
# Play), ios, all (every platform this host can build: web, android, ios),
# clean. Android release builds are signed with the upload key when
# tabcam_app/android/key.properties exists (scripts/android-keystore.sh),
# else with the debug key. Settings, from the environment or `make VAR=value`:
#   MODE          release (default), profile or debug
#   IOS_CODESIGN  1 to sign the iOS build (needs a signing team in Xcode);
#                 unsigned by default
#   WEB_BASE_HREF the web build's base href, e.g. /app/ for the deployed site
#                 (where CloudFront serves the app); / by default
# Build settings come from the repo's .env (see .env.example), through the
# same allowlist as the run scripts (scripts/dart-defines.sh).
#
# The version is X.Y.Z: X and Y from version.X.txt and version.Y.txt, Z the
# build time as YYYYMMDDHHMM (UTC); the build number is the same time in
# Unix seconds. Set VERSION_Z and BUILD_NUMBER to override them (see
# scripts/version.sh).
set -euo pipefail

MODE="${MODE:-release}"
case "$MODE" in
  release | profile | debug) ;;
  *) echo "error: MODE must be release, profile or debug (got '$MODE')" >&2; exit 2 ;;
esac

cd "$(dirname "$0")/../tabcam_app"
source ../scripts/dart-defines.sh
source ../scripts/version.sh
# TABCAM_VERSION: X.Y.Z, shown in the About dialog.
BUILD_ARGS=(--build-name "$VERSION" --build-number "$BUILD_NUMBER" ${DART_DEFINES[@]+"${DART_DEFINES[@]}"}
  --dart-define="TABCAM_VERSION=$VERSION")

# can_build <target>: whether this host's OS can build the target.
can_build() {
  case "$1" in
    ios) [[ "$(uname -s)" == Darwin ]] ;;
    *) return 0 ;;
  esac
}

build() {
  local target="$1"
  if ! can_build "$target"; then
    echo "error: $target can't be built on $(uname -s)" >&2
    return 1
  fi
  echo "==> $target ($MODE, version $VERSION, build $BUILD_NUMBER)"
  case "$target" in
    web)
      local base=()
      [[ -n "${WEB_BASE_HREF:-}" ]] && base=(--base-href "$WEB_BASE_HREF")
      flutter build web "--$MODE" ${base[@]+"${base[@]}"} "${BUILD_ARGS[@]}"
      echo "==> web: tabcam_app/build/web/"
      ;;
    android)
      flutter build apk "--$MODE" "${BUILD_ARGS[@]}"
      echo "==> android: tabcam_app/build/app/outputs/flutter-apk/app-$MODE.apk"
      ;;
    appbundle)
      flutter build appbundle "--$MODE" "${BUILD_ARGS[@]}"
      echo "==> appbundle: tabcam_app/build/app/outputs/bundle/$MODE/app-$MODE.aab"
      ;;
    ios)
      local sign=--no-codesign
      [[ "${IOS_CODESIGN:-}" == 1 ]] && sign=--codesign
      flutter build ios "--$MODE" "$sign" "${BUILD_ARGS[@]}"
      echo "==> ios: tabcam_app/build/ios/iphoneos/Runner.app"
      ;;
  esac
}

[[ $# -gt 0 ]] || set -- all
for arg in "$@"; do
  case "$arg" in
    web | android | appbundle | ios) build "$arg" ;;
    all)
      for target in web android ios; do
        if can_build "$target"; then
          build "$target"
        else
          echo "==> skipping $target: can't be built on $(uname -s)"
        fi
      done
      ;;
    clean) flutter clean ;;
    *) echo "error: unknown target '$arg' (web, android, appbundle, ios, all, clean)" >&2; exit 2 ;;
  esac
done
