# App stores

TabScan is being prepared for Google Play and the Apple App Store,
published under **personal** (individual) developer accounts: the
maintainer's name shows as the seller. A new personal Play account must
run a closed test with at least 12 testers for 14 days before it can
publish to production.

## Status

| Step | State |
|---|---|
| Developer accounts | Apple: the maintainer has one; Google Play Console: to do (maintainer) |
| Android upload key and signed App Bundle | Done (below); the upload key's OAuth client is to do |
| Store builds: hide the Premium purchase links | Done ([cloud OCR](cloud-ocr.md#in-the-app)) |
| Store builds: in-app account deletion (Profile, Delete account; the web app as the deletion URL) | Done ([cloud sync](cloud-sync.md#deleting-the-account)); needs the stacks deployed. To do with Sign in with Apple: deleting the account must also revoke the user's Apple tokens through Apple's REST API, which needs a Sign in with Apple key on a server |
| Sign in with Apple (App Store guideline 4.8) | Code done ([cloud sync](cloud-sync.md#sign-in-with-apple-ios)), off by default. To do (maintainer): join the paid Apple Developer Program (a free Personal Team can't sign the capability); enable Sign in with Apple on the App ID `com.nu01.tabscan`; deploy `tabscan-identity`, `tabscan-share-api` and `tabscan-ocr` with Apple (`AppleClientId=com.nu01.tabscan`, [tabscan_infra](../tabscan_infra/README.md)); set `TABSCANNER_APPLE_SIGN_IN=1` and the paid team in `.env`; try it on a phone |
| Privacy policy page; iOS privacy manifest and encryption declaration | Done ([privacy](privacy.md)); the contact email is still to be added |
| Play internal testing, then the 14-day closed test | To do |
| App Store Connect record, TestFlight | To do |
| Listings: descriptions, data safety, privacy labels, rating, category | Drafts done ([below](#store-listings)) |
| Listings: screenshots, feature graphic, the review test account | To do (maintainer) |
| Review submission | To do |

## Android signing

Google Play App Signing: Play keeps the **app signing key** and re-signs
what's uploaded; TabScan's builds are signed with an **upload key**.

- `bash scripts/android-keystore.sh [path]` creates the upload key once
  (RSA 4096, PKCS12, alias `upload`, valid ~27 years) at
  `~/.android-keys/tabscan-upload.jks` by default, outside the repo, and
  writes `tabscan_app/android/key.properties` (git-ignored, mode 600) with
  its path and password. Run again, it prints the key's SHA-1 and SHA-256.
  The keystore and password must be backed up (they are, in the
  maintainer's Google Drive); losing them means asking Google to reset the
  upload key.
- The Gradle build signs release builds with that key when
  `key.properties` exists, else with the debug key, so builds without it
  (other developers, pull requests) still work.
- `make appbundle` builds the App Bundle Play takes,
  `tabscan_app/build/app/outputs/bundle/release/app-release.aab`.
- The Release workflow signs with the upload key from two repository
  secrets ([release](release.md)):
  - `ANDROID_UPLOAD_KEYSTORE_BASE64`:
    `base64 -i ~/.android-keys/tabscan-upload.jks | gh secret set ANDROID_UPLOAD_KEYSTORE_BASE64`
  - `ANDROID_UPLOAD_KEYSTORE_PASSWORD`: `gh secret set ANDROID_UPLOAD_KEYSTORE_PASSWORD`
- An app installed with another key (the debug key, or Play's) can't be
  updated by `scripts/android-install.sh`; it says so, and the app must be
  uninstalled first (its unsynced events go).

Each key that signs installed apps needs, for sign-in and
[App Links](sharing.md#android-app-links):

- an **Android OAuth client** in Google Cloud for `com.nu01.tabscan` and
  the key's SHA-1;
- its SHA-256 in
  [assetlinks.json](../tabscan_index/site/.well-known/assetlinks.json).

That's the debug key, the upload key (its SHA-256 is in assetlinks.json;
its OAuth client is to do) and Play's app signing key (Play Console → Test
and release → App integrity) once the app is on Play.

## Store listings

[tabscan_store/](../tabscan_store) holds the listings, drafted in the
layout fastlane reads (`fastlane supply` for Play, `deliver` for the App
Store), so they can be uploaded later; fastlane itself isn't set up yet.

- `android/en-US/`: `title.txt` (TabScan: Guitar Tab Scanner),
  `short_description.txt`, `full_description.txt`,
  `changelogs/default.txt`; `images/` waits for the icon (512 x 512),
  feature graphic (1024 x 500) and phone screenshots, its README says
  what's needed.
- `ios/en-US/`: `name.txt` (as the Play title), `subtitle.txt` (Scan tabs
  into editable text), `description.txt` (the Play full description),
  `keywords.txt`, `promotional_text.txt`, `release_notes.txt`, the
  support and marketing URLs (https://tabscan.nu01.com/) and the privacy
  URL (https://tabscan.nu01.com/privacy). `ios/review_information/notes.txt`
  is App Review's notes (how to sign in, what to try);
  [REVIEW_NOTES.md](../tabscan_store/ios/REVIEW_NOTES.md) says what the
  maintainer must add: contact details and a Google test account, kept
  out of git (`.gitignore` ignores the folder's other files).
- [data-safety.md](../tabscan_store/data-safety.md): draft answers for
  Play's Data safety form and Apple's App Privacy labels (email, user ID,
  name, photos and videos, files, other user content; only when signed
  in; encrypted in transit; deletable in the app; nothing shared, nor
  used for ads or tracking; ML Kit's anonymous diagnostics to confirm),
  the content rating (no objectionable content; users share captures
  with people they pick), target audience (not children), category
  (Music & Audio on Play, Music on the App Store) and Play's account
  deletion URL (https://tabscan.nu01.com/app/: sign in, Profile, Delete
  account).

The text claims only what the app does and never offers to buy Premium
(the store apps don't sell it); it says Premium subscribers get cloud
transcription. Screenshots are to show made-up riffs only.
`bash scripts/store-metadata-check.sh [dir]` checks each file is there
and within its store's limit (title and name 30, subtitle 30, short
description 80, descriptions 4000, keywords 100 bytes, promotional text
170, URLs https), and exits non-zero otherwise.
