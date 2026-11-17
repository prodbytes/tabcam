#!/usr/bin/env bash
# Makes the app icon and logo (specs/app-icon.md): writes the SVG masters
# (scripts/app_icon.py, with fontTools from a throwaway venv), renders
# them to PNG with headless Chrome, generates every platform's icons
# (flutter_launcher_icons) and Play's icon and feature graphic.
#
#   bash scripts/app-icon.sh     (in devbox, on a Mac with Google Chrome)
set -euo pipefail

cd "$(dirname "$0")/.."
root="$PWD"
icons="$root/tabcam_app/assets/icon"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

python3 -m venv "$work/venv"
"$work/venv/bin/pip" install -q fonttools==4.55.3
logo_width="$("$work/venv/bin/python" -I scripts/app_icon.py)"

# render <svg> <png> <width> <height>
render() {
  printf '<html><body style="margin:0"><img src="file://%s" style="display:block;width:%spx;height:%spx"></body></html>' \
    "$1" "$3" "$4" > "$work/r.html"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars \
    --default-background-color=00000000 --force-device-scale-factor=1 \
    --window-size="$3,$4" --allow-file-access-from-files \
    --screenshot="$2" "file://$work/r.html" >/dev/null 2>&1
}
render "$icons/icon.svg" "$icons/icon.png" 1024 1024
render "$icons/icon_foreground.svg" "$icons/icon_foreground.png" 1024 1024
render "$icons/logo.svg" "$icons/logo.png" "$logo_width" 480
# The index page shows the logo too (specs/index-page.md).
cp "$icons/logo.svg" "$root/tabcam_index/site/img/logo.svg"

cd tabcam_app
flutter pub run flutter_launcher_icons
# The generator also rewrites an unrelated Xcode setting: put it back.
sed -i '' 's/ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = AppIcon;/ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;/' \
  ios/Runner.xcodeproj/project.pbxproj
flutter test screenshots/store_screenshots_test.dart \
  --plain-name 'store graphics: Play icon and feature graphic'
cd "$root"
bash scripts/store-metadata-check.sh
