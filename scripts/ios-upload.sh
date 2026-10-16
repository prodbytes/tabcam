#!/usr/bin/env bash
# Uploads the App Store build to App Store Connect (TestFlight, then review):
# exports the archive `make ipa` made (tabcam_app/build/ios/archive/
# Runner.xcarchive) with destination "upload", signed automatically for the
# team in .env (TABCAM_IOS_DEVELOPMENT_TEAM). macOS only. Run from anywhere:
#
#   make ipa && bash scripts/ios-upload.sh [archive]
#
# Authenticates as the Apple account signed in to Xcode (Settings >
# Accounts), or, when all three are set, with an App Store Connect API key
# (Users and Access > Integrations; Admin or App Manager):
#   ASC_KEY_ID      the key's ID
#   ASC_ISSUER_ID   the issuer ID
#   ASC_KEY_PATH    the AuthKey_<ID>.p8 file (outside the repo)
# The app's record (com.nu01.tabcam) must exist in App Store Connect, and
# each upload needs a new build number (make ipa uses the build time).
set -euo pipefail

cd "$(dirname "$0")/.."
archive="${1:-tabcam_app/build/ios/archive/Runner.xcarchive}"
[[ -d "$archive" ]] || { echo "error: no archive at $archive (make ipa first)" >&2; exit 1; }

team="${TABCAM_IOS_DEVELOPMENT_TEAM:-}"
[[ -z "$team" && -f .env ]] && team="$(sed -n 's/^TABCAM_IOS_DEVELOPMENT_TEAM=//p' .env | tail -1)"
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || { echo "error: TABCAM_IOS_DEVELOPMENT_TEAM isn't a team ID (environment or .env)" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# The build number stays the one make ipa set (manageAppVersionAndBuildNumber
# off), so it matches the release's.
cat > "$work/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>destination</key><string>upload</string>
  <key>method</key><string>app-store-connect</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$team</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
  <key>stripSwiftSymbols</key><true/>
</dict>
</plist>
EOF

auth=()
if [[ -n "${ASC_KEY_ID:-}" && -n "${ASC_ISSUER_ID:-}" && -n "${ASC_KEY_PATH:-}" ]]; then
  auth=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
    -authenticationKeyPath "$ASC_KEY_PATH")
fi

echo "==> uploading $archive to App Store Connect (team $team)"
xcodebuild -exportArchive -archivePath "$archive" \
  -exportOptionsPlist "$work/ExportOptions.plist" -exportPath "$work/export" \
  -allowProvisioningUpdates ${auth[@]+"${auth[@]}"}
echo "==> uploaded: App Store Connect > TabCam > TestFlight shows it once processed"
