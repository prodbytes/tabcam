#!/usr/bin/env bash
# Serves the Flutter app in web mode on http://localhost:${FLUTTER_WEB_PORT}/app/:
# a debug build with hot reload, or a release build with TABCAM_WEB_RELEASE=1.
# The /app/ base href matches the path the CloudFront distribution routes to
# the app (see tabcam_infra/site.yaml).
# Runs via `devbox services up` (see process-compose.yaml) or `devbox run web`.
# Uses the web-server device, so no Chrome is needed; open the URL in any browser.
# On the web, scanning takes a photo (no edge detection) and Read tab is
# off: see specs/platforms.md.
set -euo pipefail

PORT="${FLUTTER_WEB_PORT:-2012}"
# 127.0.0.1, not localhost: Dart binds "localhost" to IPv6 [::1] only.
# TABCAM_BIND_HOST=0.0.0.0 serves other devices on the network (a phone's
# browser, say).
HOST="${TABCAM_BIND_HOST:-127.0.0.1}"

cd "$(dirname "$0")/../tabcam_app"
# Local web sign-in uses the "local - web" OAuth client, whose JavaScript
# origins are the local URLs (TABCAM_GOOGLE_WEB_CLIENT_ID is the
# production client, which manual deploys read from .env too).
_local_client="${TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID:-$(sed -n 's/^TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID=//p' ../.env 2>/dev/null | tail -1)}"
[[ -n "$_local_client" ]] && export TABCAM_GOOGLE_WEB_CLIENT_ID="$_local_client"
# A Cognito pool trusts one Google client, so the local client's tokens go
# to the local pool (tabcam-identity-local).
_local_pool="${TABCAM_COGNITO_LOCAL_IDENTITY_POOL_ID:-$(sed -n 's/^TABCAM_COGNITO_LOCAL_IDENTITY_POOL_ID=//p' ../.env 2>/dev/null | tail -1)}"
if [[ -n "$_local_client" && -n "$_local_pool" ]]; then
  export TABCAM_COGNITO_IDENTITY_POOL_ID="$_local_pool"
elif [[ -n "$_local_client" ]]; then
  echo "warning: TABCAM_COGNITO_LOCAL_IDENTITY_POOL_ID isn't set; the identity pool will refuse the local client's tokens" >&2
fi
source ../scripts/dart-defines.sh
source ../scripts/version.sh
flutter pub get

# TABCAM_WEB_RELEASE=1 (in the environment or .env) serves a release build
# instead: one compiled main.dart.js rather than the debug build's ~1,500
# modules, which a busy machine takes minutes to load through Floci. No hot
# reload: restart the service to rebuild after a change.
_release="${TABCAM_WEB_RELEASE:-$(sed -n 's/^TABCAM_WEB_RELEASE=//p' ../.env 2>/dev/null | tail -1)}"
if [[ "$_release" == 1 ]]; then
  flutter build web --release --base-href /app/ \
    ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} --dart-define="TABCAM_VERSION=$VERSION"
  # Served under /app/, as CloudFront routes it: a folder whose app/ is the
  # build. The app uses hash URLs, so a static server needs no rewrites.
  root="$(mktemp -d)"
  trap 'rm -rf "$root"' EXIT
  ln -s "$PWD/build/web" "$root/app"
  echo "Serving the release build on http://$HOST:$PORT/app/"
  # Not exec: the trap removes the folder when the server stops.
  python3 -m http.server "$PORT" --bind "$HOST" --directory "$root"
  exit
fi

# The About dialog shows X.Y.Z, Z being when this server started.
exec flutter run -d web-server --web-hostname "$HOST" --web-port "$PORT" \
  --base-href /app/ \
  ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} --dart-define="TABCAM_VERSION=$VERSION"
