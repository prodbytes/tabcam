#!/usr/bin/env bash
# Serves the Flutter app in web mode on http://localhost:${FLUTTER_WEB_PORT}/app/.
# The /app/ base href matches the path the CloudFront distribution routes to
# the app (see tabscan_infra/site.yaml).
# Runs via `devbox services up` (see process-compose.yaml) or `devbox run web`.
# Uses the web-server device, so no Chrome is needed; open the URL in any browser.
# On the web, scanning takes a photo (no edge detection) and Read tab is
# off: see specs/platforms.md.
set -euo pipefail

PORT="${FLUTTER_WEB_PORT:-2012}"
# 127.0.0.1, not localhost: Dart binds "localhost" to IPv6 [::1] only.
# TABSCANNER_BIND_HOST=0.0.0.0 serves other devices on the network (a phone's
# browser, say).
HOST="${TABSCANNER_BIND_HOST:-127.0.0.1}"

cd "$(dirname "$0")/../tabscan_app"
# Local web sign-in uses the "local - web" OAuth client, whose JavaScript
# origins are the local URLs (TABSCANNER_GOOGLE_WEB_CLIENT_ID is the
# production client, which manual deploys read from .env too).
_local_client="${TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID:-$(sed -n 's/^TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID=//p' ../.env 2>/dev/null | tail -1)}"
[[ -n "$_local_client" ]] && export TABSCANNER_GOOGLE_WEB_CLIENT_ID="$_local_client"
# A Cognito pool trusts one Google client, so the local client's tokens go
# to the local pool (tabscan-identity-local).
_local_pool="${TABSCANNER_COGNITO_LOCAL_IDENTITY_POOL_ID:-$(sed -n 's/^TABSCANNER_COGNITO_LOCAL_IDENTITY_POOL_ID=//p' ../.env 2>/dev/null | tail -1)}"
if [[ -n "$_local_client" && -n "$_local_pool" ]]; then
  export TABSCANNER_COGNITO_IDENTITY_POOL_ID="$_local_pool"
elif [[ -n "$_local_client" ]]; then
  echo "warning: TABSCANNER_COGNITO_LOCAL_IDENTITY_POOL_ID isn't set; the identity pool will refuse the local client's tokens" >&2
fi
source ../scripts/dart-defines.sh
source ../scripts/version.sh
flutter pub get
# The About dialog shows X.Y.Z, Z being when this server started.
exec flutter run -d web-server --web-hostname "$HOST" --web-port "$PORT" \
  --base-href /app/ \
  ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} --dart-define="TABSCANNER_VERSION=$VERSION"
