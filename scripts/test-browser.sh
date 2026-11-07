#!/usr/bin/env bash
# Runs the browser tests (`@TestOn('browser')`: the web take recorder, the
# web video editor) in Chrome: `bash scripts/test-browser.sh [test files]`.
# Chrome is started with sound allowed without a tap
# (--autoplay-policy=no-user-gesture-required), which the editor's test
# needs to record a tone; `flutter test` has no flag for that, so Chrome is
# wrapped. CHROME_EXECUTABLE, if set, names the Chrome to wrap.
set -euo pipefail

chrome="${CHROME_EXECUTABLE:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
if [[ ! -x "$chrome" ]]; then
  chrome="$(command -v google-chrome || command -v chromium || true)"
fi
if [[ -z "$chrome" ]]; then
  echo "error: no Chrome found; set CHROME_EXECUTABLE" >&2
  exit 1
fi
wrapper="$(mktemp -d)/chrome"
cat > "$wrapper" <<WRAP
#!/bin/sh
exec "$chrome" --autoplay-policy=no-user-gesture-required "\$@"
WRAP
chmod +x "$wrapper"
trap 'rm -rf "$(dirname "$wrapper")"' EXIT

cd "$(dirname "$0")/../tabcam_app"
tests=("$@")
if [[ ${#tests[@]} -eq 0 ]]; then
  tests=(test/web_take_recorder_test.dart test/web_video_editor_test.dart)
fi
CHROME_EXECUTABLE="$wrapper" flutter test --platform chrome "${tests[@]}"
