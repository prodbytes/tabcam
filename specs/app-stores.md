# App stores

TabCam is being prepared for Google Play and the Apple App Store,
published under **personal** (individual) developer accounts: the
maintainer's name shows as the seller. A new personal Play account must
run a closed test with at least 12 testers for 14 days before it can
publish to production.

## Status

| Step | State |
|---|---|
| Developer accounts | Apple: the maintainer has one; Google Play Console: personal, account 5720098115371031326, verified (2026-10-19) |
| Android upload key and signed App Bundle | Done (below); the upload key's OAuth client is to do |
| Store builds: hide the Premium purchase links | Done ([cloud OCR](cloud-ocr.md#in-the-app)) |
| Store builds: in-app account deletion (Profile, Delete account, in the app or the web app; the privacy page, which says how, as Play's deletion URL) | Done ([cloud sync](cloud-sync.md#deleting-the-account)), stacks deployed. Deleting an Apple account revokes its Apple tokens through Apple's REST API ([cloud sync](cloud-sync.md#revoking-apples-tokens)); its Sign in with Apple key is in the SSM parameter `/tabcam/apple-sign-in-key` (set 2026-10-16, [tabcam_infra](../tabcam_infra/README.md)) |
| Sign in with Apple (App Store guideline 4.8) | Done ([cloud sync](cloud-sync.md#sign-in-with-apple-ios-and-android)): `tabcam-identity`, `tabcam-share-api` and `tabcam-ocr` deployed with `AppleClientId=com.nu01.tabcam` (2026-10-16), `TABCAM_APPLE_SIGN_IN=1` and the paid team in the maintainer's `.env`. Tried on the maintainer's iPhone with TestFlight build 1792173901 (2026-10-17) |
| Privacy policy page; iOS privacy manifest and encryption declaration | Done ([privacy](privacy.md)), contact privacy@nu01.com |
| Play internal testing, then the 14-day closed test | The app is in Play Console (2026-10-19): TabCam: Guitar Tab Camera, `com.nu01.tabcam`, app ID 4975838614790670668, free, en-US, Play App Signing. Its first App Bundle, `0.2.202610171415-GA`'s (versionCode 1792246557), uploaded by hand to an internal testing release, rolled out to the internal tester list **Internal** (the maintainer's account; opt-in link https://play.google.com/apps/internaltest/4701188091177325656) with `changelogs/default.txt` as its notes. Then `0.2.202610191330-GA`'s (versionCode 1792416626, the camera's camera permission fix), uploaded by hand and rolled out to **Internal** (2026-10-19). To do: a service account for the uploads, then the closed test. 2026-10-20/21: 0.2.202610201627 (versionCode 1792513648) rolled out to **Internal**; the default listing set to the repo's (title "TabCam: Guitar Tab Camera", the camera wording, no Premium line) and sent for review with Google (2026-10-21). 0.2.202610210617 (the first build with Sign in with Apple on Android) built, to upload. Production waits for the closed test on **Alpha**: 12 opted-in testers (1 so far) for 14 days |
| App Store distribution build (`make ipa`) and its upload (`scripts/ios-upload.sh`) | Done ([below](#ios-distribution)): 0.2.202610191330 (build 1792417537, the `0.2.202610191330-GA` release's commit), uploaded 2026-10-19 for TestFlight; 0.2.202610171102 (build 1792234961, the `0.2.202610171102-GA` release's commit), the one to submit, built, signed and uploaded 2026-10-17; before it 0.2.202610171036 (build 1792233362) and the first, 0.1.202610161805 (build 1792173901, 2026-10-16) |
| App Store Connect record, TestFlight | Done: "TabCam: Guitar Tab Camera", Apple ID 6823729635, team LMX88986F3. Build 1792173901 processed, no non-exempt encryption (from `Info.plist`), in the internal TestFlight group **Internal** with the account holder (2026-10-16, [below](#uploading-the-app-store-listing)), and tested on the maintainer's iPhone, all working (2026-10-17); no external testers. Build 1792234961 added to **Internal** and the listing's version renamed to 0.2.202610171102 (`store-upload-ios.sh metadata 0.2.202610171102`), 2026-10-17. Build 1792417537 (0.2.202610191330) added to **Internal** (`store-upload-ios.sh testflight 1792417537`), 2026-10-19 |
| Listings: descriptions, data safety, privacy labels, rating, category | Done for the App Store: the metadata uploaded 2026-10-16 ([below](#uploading-the-app-store-listing)): description, keywords, promotional text, URLs, name, subtitle, review notes, screenshots, Music and Productivity, copyright, age rating; by the maintainer in App Store Connect's web UI: the App Privacy labels ([data-safety.md](../tabcam_store/data-safety.md)), free, all 175 territories (new ones too), the content rights (no third-party content). Play (2026-10-19, in Play Console's web UI): the default store listing (title, short and full descriptions, icon, feature graphic, phone screenshots 1 to 6 in order; no AI-generated assets), Music & Audio, contact privacy@nu01.com and https://tabcam.nu01.com/, privacy policy URL, no ads, no advertising ID (the bundle has no `AD_ID` permission), not a government app, no financial or health features, the IARC rating (All Other App Types; users share content, limited to people given the link; L in Brazil, Everyone, PEGI 3), Data safety ([data-safety.md](../tabcam_store/data-safety.md)'s answers plus Voice or sound recordings (Cam's takes), all required, for app functionality (email and user IDs also account management), ML Kit's diagnostics and device IDs for analytics, OAuth sign-in, deletion URL https://tabcam.nu01.com/privacy), Sign in details (the reviewers' Google account, nu01test@gmail.com, with Premium; its password entered by the maintainer, kept out of git) and Target audience: 18 and over (2026-10-19). Any group under 18 brings Play's Families policy for users counted as children in some countries (COPPA, GDPR: sign-in, synced content, ML Kit's diagnostics, sharing), so younger groups wait for an age check and a mode for them; the Everyone rating still lets anyone install it, and "restrict users Google determines to be minors" is off |
| Listings: icon, feature graphic, screenshots (Play phone, 6.9" iPhone, 13" iPad) | Done ([below](#store-graphics)) |
| Listings: App Review's contact details | Done (maintainer, 2026-10-17; [REVIEW_NOTES.md](../tabcam_store/ios/REVIEW_NOTES.md)) |
| Review submission | App Store: 0.2.202610171415 rejected 2026-10-20 (guidelines 2.3.10, Android status bars in the iOS screenshots, and 2.1(b), Premium mentioned with nothing to buy); 0.2.202610201114 (build 1792494901, with the fixes, the listing and screenshots uploaded again) resubmitted 2026-10-20, Waiting for Review, manual release. Before: 0.2.202610171415 (build 1792246500, single Share and file links) submitted 2026-10-18; it replaced 0.2.202610171102 (build 1792234961), withdrawn before review started, the version renamed and its listing and screenshots uploaded again. Play: the closed testing track **Alpha** is ready (all 178 countries, the **Internal** list, feedback to privacy@nu01.com, the 1792246557 bundle), with 16 changes waiting to be submitted for review. Not submitted yet: Google sign-in fails in the build Play signs until Play's key has its Android OAuth client. Then the 14-day closed test with 12 opted-in testers, then applying for production |

## iOS distribution

The App Store build is signed by the maintainer's paid team
(`TABCAM_IOS_DEVELOPMENT_TEAM` in `.env`), with automatic signing:

- `make ipa` (macOS) archives a release build with `.env`'s settings
  (Sign in with Apple's entitlement among them, [cloud sync](cloud-sync.md#sign-in-with-apple-ios-and-android))
  and exports it for the App Store (`flutter build ipa --export-method
  app-store`): `tabcam_app/build/ios/archive/Runner.xcarchive` and
  `tabcam_app/build/ios/ipa/TabCam.ipa`. Xcode makes the Apple
  Distribution certificate and the App Store profile itself
  (`-allowProvisioningUpdates`, as the Apple account signed in to Xcode),
  and keeps the App ID's capabilities in step with the entitlements. The
  version and build number are the release's ([release](release.md#versioning)).
- `bash scripts/ios-upload.sh [archive]` uploads that archive to App
  Store Connect (`xcodebuild -exportArchive`, destination `upload`, the
  build number left as it is), as the account signed in to Xcode, or with
  an App Store Connect API key when `ASC_KEY_ID`, `ASC_ISSUER_ID` and
  `ASC_KEY_PATH` are set. The app's record must exist first ("App record
  with bundle identifier com.nu01.tabcam not found" otherwise), and each
  upload needs a new build (`make ipa` again).
- Not in CI: the Release workflow's iOS build stays unsigned
  ([release](release.md)).

## Android signing

Google Play App Signing: Play keeps the **app signing key** and re-signs
what's uploaded; TabCam's builds are signed with an **upload key**.

- `bash scripts/android-keystore.sh [path]` creates the upload key once
  (RSA 4096, PKCS12, alias `upload`, valid ~27 years) at
  `~/.android-keys/tabcam-upload.jks` by default, outside the repo, and
  writes `tabcam_app/android/key.properties` (git-ignored, mode 600) with
  its path and password. Run again, it prints the key's SHA-1 and SHA-256.
  The keystore and password must be backed up (they are, in the
  maintainer's Google Drive); losing them means asking Google to reset the
  upload key.
- The Gradle build signs release builds with that key when
  `key.properties` exists, else with the debug key, so builds without it
  (other developers, pull requests) still work.
- `make appbundle` builds the App Bundle Play takes,
  `tabcam_app/build/app/outputs/bundle/release/app-release.aab`.
- The Release workflow signs with the upload key from two repository
  secrets ([release](release.md)):
  - `ANDROID_UPLOAD_KEYSTORE_BASE64`:
    `base64 -i ~/.android-keys/tabcam-upload.jks | gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64`
  - `ANDROID_UPLOAD_KEYSTORE_PASSWORD`: `gh secret set ANDROID_UPLOAD_KEYSTORE_PASSWORD`
- An app installed with another key (the debug key, or Play's) can't be
  updated by `scripts/android-install.sh`; it says so, and the app must be
  uninstalled first (its unsynced events go).

Each key that signs installed apps needs, for sign-in and
[App Links](sharing.md#android-app-links):

- an **Android OAuth client** in TabCam's Google Cloud project,
  `tabcam-nu01` (project number 91614266636, the web client's: Google
  refuses an Android client in another project with "Android clients and
  Web clients (server client ID) must be in the same project", error
  28444), for `com.nu01.tabcam` and the key's SHA-1, added to
  `tabcam-identity`'s `GoogleAppClientIds`
  (the identity pool refuses tokens of a client it doesn't list,
  [cloud sync](cloud-sync.md#googles-token));
- its SHA-256 in
  [assetlinks.json](../tabcam_index/site/.well-known/assetlinks.json).

That's the debug key, the upload key and Play's app signing key (Play
Console → Protected with Play → App signing; SHA-1
1E:12:2A:0C:D1:E9:26:B0:08:CD:9B:79:12:30:E1:D2:D4:34:97:47). All three
SHA-256s are in assetlinks.json. Play's OAuth client was first made in
the old TabScan project (`tabscan-511213`, 1061413485511) by mistake, so
Google still refuses it; Play's and the upload key's clients in
`tabcam-nu01` are to do (Google Cloud Console → Clients, Android,
`com.nu01.tabcam` and the SHA-1), and until Play's exists, Google sign-in
fails in the app installed from Play.

## Store listings

[tabcam_store/](../tabcam_store) holds the listings, in the layout
fastlane reads (`fastlane supply` for Play, `deliver` for the App Store).
The App Store's are uploaded with `scripts/store-upload-ios.sh`
([below](#uploading-the-app-store-listing)), Play's with
`scripts/store-upload-android.sh` ([below](#uploading-to-google-play)).

- `android/en-US/`: `title.txt` (TabCam: Guitar Tab Camera),
  `short_description.txt`, `full_description.txt`,
  `changelogs/default.txt`; `images/`: `icon.png`, `featureGraphic.png`
  and `phoneScreenshots/1.png` … `6.png` ([below](#store-graphics)).
- `ios/metadata/en-US/`: `name.txt` (as the Play title), `subtitle.txt` (Scan tabs
  into editable text), `description.txt` (the Play full description,
  but for its sign-in line: Apple or Google on iOS, Google on Play),
  `keywords.txt`, `promotional_text.txt`, `release_notes.txt`, the
  support and marketing URLs (https://tabcam.nu01.com/) and the privacy
  URL (https://tabcam.nu01.com/privacy); `ios/screenshots/en-US/`, the
  screenshots ([below](#store-graphics)). `ios/metadata/review_information/notes.txt`
  is App Review's notes (the welcome's Sign in with Apple and Google, any
  Apple ID or Google account working; what to try: Scan, the Text view
  and Verified, Cam, Share, Add, Delete account);
  [REVIEW_NOTES.md](../tabcam_store/ios/REVIEW_NOTES.md) says what the
  maintainer must add: contact details and, if wanted, a Google test
  account, kept out of git (`.gitignore` ignores the folder's other
  files). `ios/age-rating.json` is the age rating. The metadata is in
  `ios/metadata/`, not `ios/`, since `deliver` takes every folder of its
  metadata path for a language, and `ios/screenshots/` isn't one.
- [data-safety.md](../tabcam_store/data-safety.md): draft answers for
  Play's Data safety form and Apple's App Privacy labels (email, user ID,
  name, photos and videos, files, other user content; only when signed
  in; encrypted in transit; deletable in the app; nothing shared, nor
  used for ads or tracking; ML Kit's anonymous diagnostics to confirm;
  required, since the app needs signing in), the content rating (no
  objectionable content; users share captures with people they pick or
  by a read-only link; no chat; Cam's play-along web view, answered as
  no unrestricted web access), target audience (not children), category
  (Music & Audio on Play, Music on the App Store) and Play's account
  deletion URL (https://tabcam.nu01.com/privacy, which says how: Profile,
  Delete account, in the app or the web app).

The text claims only what the app does as it is now (App Store guideline
2.3): signing in first (signed out there's only the welcome), scanning
and adding, reading tabs on the device, the Text view's tools (Copy,
Verified; not Fix, hidden for now), Cam, the zip download, Share copying a
read-only link (signed in, kept in Shared with me). It doesn't mention
Premium: the store apps don't sell it, and App Review took a mention of a
subscription it couldn't buy as a broken in-app purchase (guideline
2.1(b), 2026-10-20). The review notes say the app has no in-app
purchases or subscriptions.
`bash scripts/store-metadata-check.sh [dir]` checks each file is there
and within its store's limit (title and name 30, subtitle 30, short
description 80, descriptions 4000, keywords 100 bytes, promotional text
170, URLs https), and exits non-zero otherwise.

## Uploading the App Store listing

`bash scripts/store-upload-ios.sh` runs fastlane
([tabcam_store/fastlane/](../tabcam_store/fastlane/Fastfile), from
`tabcam_store/`; `brew install fastlane`) with an App Store Connect API
key, as `scripts/ios-upload.sh` takes one: `ASC_KEY_ID`, `ASC_ISSUER_ID`
and `ASC_KEY_PATH` (the `.p8`, outside the repo; the maintainer's is an
App Manager key in `~/.apple-keys/`).

- `metadata [app version]`: `scripts/store-metadata-check.sh`, then
  `deliver` for `com.nu01.tabcam`: the metadata (`ios/metadata`), the
  screenshots (`ios/screenshots`, replacing those there: `deliver` tells
  the display type by the size, 1320 x 2868 the 6.9" iPhone,
  `APP_IPHONE_67`, and 2064 x 2752 the 13" iPad,
  `APP_IPAD_PRO_3GEN_129`), primary category Music and secondary
  Productivity, the copyright "2026 Julio Machado Faerman" and the age
  rating (`ios/age-rating.json`: "None" throughout; no unrestricted web
  access, messaging, ads, social media, gambling, loot boxes, health
  topics, parental controls or age assurance; user-generated content
  yes). With a version (the build's, `0.1.202610161805`), the version
  App Store Connect prepares is renamed to it first, so the build can
  go with it. No binary, no submission for review, manual release.
  `deliver` skips `release_notes.txt` on the app's first version (Apple
  takes none), and uploads the contact and demo account files only when
  they're there.
- `testflight <build number> [emails]`: once the build is processed,
  sets its export compliance if App Store Connect still asks (the
  build's `Info.plist` already answers: no non-exempt encryption), makes
  the internal group **Internal** if missing (by the API itself:
  fastlane's `create_beta_group` sends public link attributes App Store
  Connect refuses for internal groups), adds the build to it, and adds
  the team users given, or else the account holder, as its testers (one already in the group
  is left as it is, so the lane can run again). No external testers.

## Uploading to Google Play

`bash scripts/store-upload-android.sh` runs fastlane `supply`
([tabcam_store/fastlane/](../tabcam_store/fastlane/Fastfile), from
`tabcam_store/`) with a Google Cloud service account's JSON key, kept
outside the repo, at `PLAY_JSON_KEY_PATH`; the service account is invited
in Play Console (Users and permissions) with access to the app.

- `metadata`: `scripts/store-metadata-check.sh`, then the listing in
  `android/en-US/` (title, short and full descriptions, icon, feature
  graphic, phone screenshots). No build.
- `upload [aab | release tag] [track] [draft|completed]`: a signed App
  Bundle to a testing track, with `changelogs/default.txt` as its notes.
  The bundle is `make appbundle`'s, a path, or a release tag's
  (`tabcam-<tag>-android.aab`, downloaded with `gh`, signed by the
  Release workflow with the upload key). The track defaults to
  `internal`, the status to `draft` (all Play takes before the app's
  first review); `completed` rolls it out to the track's testers. The
  script and the lane refuse the production track.

Play's API can't make the app: it's made in Play Console (as are the
Data safety, content rating, target audience and app access forms, from
[data-safety.md](../tabcam_store/data-safety.md)), and its first App
Bundle is uploaded there by hand. Each upload needs a new versionCode
(the release's build number, [release](release.md#versioning)).

## Submitting for review

`bash scripts/store-submit-ios.sh` (fastlane lanes `withdraw` and `submit`
in [tabcam_store/fastlane/](../tabcam_store/fastlane/Fastfile), with the
App Store Connect API key, as the upload scripts):

- `withdraw`: cancels the submission waiting for review (App Store
  Connect refuses one already in review); the version can change again.
- `submit <app version> <build number>`: refuses while a submission is
  waiting for or in review; attaches the processed build to that version,
  then submits the rejected submission again (state Unresolved Issues,
  its rejected item marked resolved, as App Store Connect's "Resubmit to
  App Review" does), or else reuses one being put together, or makes one,
  with the version.
  Released by hand once approved.

To swap the build of a version waiting for review: `withdraw`, then
`store-upload-ios.sh metadata <new version>` (renames the version and
uploads the listing), then `submit`.

## Store graphics

`bash scripts/store-screenshots.sh` renders them all into `tabcam_store/`
and checks them. A widget test,
[store_screenshots_test.dart](../tabcam_app/screenshots/store_screenshots_test.dart)
(in `tabcam_app/screenshots/`, so `flutter test` leaves it out, and
nothing of it ships), pumps the real app (`TabCamApp`), signed in with a
fake account (`ana@example.com`) and its fake cloud (the test fakes), over
ten made-up captures: printed pages of made-up riffs that the test draws,
each with its text tab. Only made-up riffs and `example.com` addresses
show. Text is in Roboto (from the Flutter SDK) and, for iOS, San Francisco
(the Mac's system font, as iOS shows it), with the Material icons; a
status bar is drawn over the top, each platform's own: Material's
signal, Wi-Fi and battery icons on Android, and on iOS Apple's glyphs,
drawn (signal bars, Wi-Fi fan, battery), the iPad's with the date and no
signal (App Review refused Android status bars on iOS screenshots,
guideline 2.3.10, 2026-10-20); the camera's picture in Cam is a drawn
guitar neck.

| Store | Files | Size |
|---|---|---|
| Play | `android/en-US/images/icon.png` | 512 x 512, RGBA (the [app icon](app-icon.md)) |
| Play | `android/en-US/images/featureGraphic.png` | 1024 x 500, RGB: the icon, "TabCam", "Scan guitar tabs into editable text", a page of tab |
| Play | `android/en-US/images/phoneScreenshots/1.png` … `6.png` | 1080 x 1920 (411 x 731 dp at 2.625) |
| App Store | `ios/screenshots/en-US/iphone69_1.png` … `6.png` | 1320 x 2868, the 6.9" iPhone (440 x 956 pt at 3x) |
| App Store | `ios/screenshots/en-US/ipad13_1.png` … `6.png` | 2064 x 2752, the 13" iPad (1032 x 1376 pt at 2x): the app runs on iPads (`TARGETED_DEVICE_FAMILY` 1,2), so Apple asks for them |

Screenshots are RGB PNGs, without alpha. The six, in order: the Text view
of a read tab; its page with the Tab filter; Home; Capture; Cam; Share
("Link copied"). They're uploaded (2026-10-18, with 0.2.202610171415). `scripts/store-metadata-check.sh` checks each
image's size and whether it has alpha.
