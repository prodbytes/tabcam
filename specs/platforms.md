# Platforms

| | Android | iOS | Web |
|---|---|---|---|
| Minimum | 7.0 (API 24) | 15.5 | A current browser |
| Scan | System document scanner (ML Kit, base mode: no filters): edges, straightening, several pages | System document scanner (VisionKit) | TabScan's camera screen (the browser's camera): several pages, cropped to the page when one stands out |
| Add photos & videos, files | Photo picker; system file picker | Photo library; Files app | Browser file picker (both) |
| Play videos | From the file | From the file | From memory |
| Open links (`url_launcher`) | Browser, or the app for the link | Safari, or the app for the link | A new tab |
| Reading tabs (by itself) | ✅ ML Kit on the device | ✅ ML Kit on the device | Premium only (else the Text view says it needs the app) |
| Library | Files in the app's documents | Files in the app's documents | Memory, until the tab closes |
| Share | System share sheet | System share sheet | Web Share, or downloads |
| Capture links ([opening](sharing.md#opening-a-link)) | App Links: the site's links open in the app | In Safari (the web app) | The web app |
| Sign-in ([cloud sync](cloud-sync.md)) | Credential Manager | Google Sign-In SDK | Google's button (FedCM); the session kept in `localStorage` |
| TabScan Premium ([cloud OCR](cloud-ocr.md#in-the-app)) | Works if bought on the web; no purchase links | Works if bought on the web; no purchase links | Upgrade offer: Upgrade, Redeem a voucher, the event screen hint |
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

**iOS privacy declarations** ([privacy](privacy.md)):

- `Info.plist` sets `ITSAppUsesNonExemptEncryption` to false, so App
  Store Connect doesn't ask about export compliance for each build. The
  app's only cryptography is HTTPS (the OS's) and SigV4 request signing
  (SHA-256 and HMAC from the `crypto` package): authentication, which is
  exempt.
- `Runner/PrivacyInfo.xcprivacy`, in the Runner target's resources (so
  it's at the root of `Runner.app`), is the app's own privacy manifest: no
  tracking, no tracking domains; collected, linked to the user, for app
  functionality only: email address, name, user ID (the Cognito identity
  ID), photos or videos, and other user content. The app's own code (two
  stock Swift delegates; Dart files are read through Flutter) uses no
  required-reason APIs, so it declares none. Plugins and SDKs bundle
  their own manifests (Flutter, ML Kit, Google Sign-In, GoogleUtilities,
  GoogleDataTransport, the plugins); GoogleDataTransport, which ML Kit
  uses, declares other diagnostic data (not linked, analytics), to
  reflect in the App Store privacy labels.

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
its signing key: release builds are signed with the upload key when
`tabscan_app/android/key.properties` is set up, else with the debug key
([app stores](app-stores.md#android-signing)).
The app is named **TabScan** everywhere.

The web build is deployed to https://tabscan.nu01.com/app/
([deploy](deploy.md)).
