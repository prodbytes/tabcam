# Platforms

| | Android | iOS | Web |
|---|---|---|---|
| Minimum | 7.0 (API 24) | 15.5 | A current browser |
| Scan | System document scanner (ML Kit): edges, straightening, several pages | System document scanner (VisionKit) | TabScan's camera screen (the browser's camera): several pages, uncropped |
| Add photos & videos, files | Photo picker; system file picker | Photo library; Files app | Browser file picker (both) |
| Play videos | From the file | From the file | From memory |
| Open links (`url_launcher`) | Browser, or the app for the link | Safari, or the app for the link | A new tab |
| Read tab | ✅ ML Kit on the device | ✅ ML Kit on the device | ❌ (says it needs the app) |
| Library | Files in the app's documents | Files in the app's documents | Memory, until the tab closes |
| Share | System share sheet | System share sheet | Web Share, or downloads |
| Sign-in ([cloud sync](cloud-sync.md)) | Credential Manager | Google Sign-In SDK | Google's button (FedCM); the session kept in `localStorage` |
| Synced events | Kept in the app's documents | Kept in the app's documents | Downloaded again on each visit |

**iOS signing**: automatic, with each developer's own team:
`TABSCANNER_IOS_DEVELOPMENT_TEAM` in `.env` (a free Personal Team works) is written by
`scripts/dart-defines.sh` to the git-ignored
`tabscan_app/ios/Flutter/Private.xcconfig`, which `Debug.xcconfig` and
`Release.xcconfig` include; no team is committed. The same file gets
`GOOGLE_REVERSED_CLIENT_ID`, from `TABSCANNER_GOOGLE_IOS_CLIENT_ID`: the URL scheme
in `Info.plist` that Google sign-in returns to. Without it, iOS builds
are unsigned (CI's are). On a phone, a free team's app opens only after
trusting its certificate (Settings → General → VPN & Device Management),
and must be reinstalled every 7 days. `bash scripts/flutter-run.sh -d
<iPhone id> --release` builds, signs and installs it.

**iOS dependencies** come two ways: Google sign-in (`google_sign_in`)
through Swift Package Manager, its versions pinned in the committed
`Package.resolved` files (`ios/Runner.xcworkspace/xcshareddata/swiftpm/`
and the same under `Runner.xcodeproj/project.xcworkspace/`), so every
build resolves the same ones; ML Kit (text recognition, the document
scanner) through CocoaPods, which doesn't support Swift Package Manager
yet. Both bring Google's `GoogleUtilities` and `FBLPromises`, so the app
holds two copies, and iOS warns at launch ("Class … is implemented in
both … may cause spurious casting failures and mysterious crashes"). No
failure has been traced to it so far.

App IDs: `com.nu01.tabscan` (Android application ID and iOS bundle ID).
Google's Android OAuth client matches the app by that ID and the SHA-1 of
its signing key (release builds are signed with the debug key for now).
The app is named **TabScan** everywhere.

The web build is deployed to https://tabscan.nu01.com/app/
([deploy](deploy.md)).
