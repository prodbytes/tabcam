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
source ../scripts/dart-defines.sh
source ../scripts/version.sh
flutter pub get
# The About dialog shows X.Y.Z, Z being when this server started.
exec flutter run -d web-server --web-hostname "$HOST" --web-port "$PORT" \
  --base-href /app/ \
  ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} --dart-define="TABSCANNER_VERSION=$VERSION"
