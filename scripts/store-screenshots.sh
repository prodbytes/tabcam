#!/usr/bin/env bash
# Renders the store graphics into tabcam_store/: Play's icon (512 x 512),
# feature graphic (1024 x 500) and phone screenshots (1080 x 1920), and the
# App Store's 6.9" iPhone (1320 x 2868) and 13" iPad (2064 x 2752)
# screenshots. They're the real app's screens, signed in with a fake
# account over made-up captures, rendered by a widget test
# (tabcam_app/screenshots/, not part of `flutter test`); on a Mac, iOS's
# are in San Francisco, from the system's fonts. Then checks them.
#
#   bash scripts/store-screenshots.sh
set -euo pipefail

cd "$(dirname "$0")/.."
(cd tabcam_app && flutter test screenshots/store_screenshots_test.dart)
bash scripts/store-metadata-check.sh
