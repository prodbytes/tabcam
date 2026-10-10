#!/usr/bin/env bash
# Runs the app on a device with the settings from the repo's .env, e.g.
# `bash scripts/flutter-run.sh -d <device-id>`. Extra arguments go to
# `flutter run`.
set -euo pipefail

cd "$(dirname "$0")/../tabscan_app"
source ../scripts/dart-defines.sh
source ../scripts/version.sh
# The About dialog shows X.Y.Z, Z being when this run started.
exec flutter run ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} --dart-define="TABSCAN_VERSION=$VERSION" "$@"
