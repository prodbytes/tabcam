# App stores

TabScan is being prepared for Google Play and the Apple App Store,
published under **personal** (individual) developer accounts: the
maintainer's name shows as the seller. A new personal Play account must
run a closed test with at least 12 testers for 14 days before it can
publish to production.

## Status

| Step | State |
|---|---|
| Developer accounts (Apple Developer Program, Google Play Console) | To do (maintainer) |
| Android upload key and signed App Bundle | Done (below); the key itself is still to be created |
| Store builds: hide the Premium purchase links, in-app account deletion | To do |
| Sign in with Apple (App Store guideline 4.8) | To do |
| Privacy policy page; iOS privacy manifest and encryption declaration | Done ([privacy](privacy.md)); the contact email is still to be added |
| Play internal testing, then the 14-day closed test | To do |
| App Store Connect record, TestFlight | To do |
| Listings: screenshots, descriptions, data safety, privacy labels, rating | To do |
| Review submission | To do |

## Android signing

Google Play App Signing: Play keeps the **app signing key** and re-signs
what's uploaded; TabScan's builds are signed with an **upload key**.

- `bash scripts/android-keystore.sh [path]` creates the upload key once
  (RSA 4096, PKCS12, alias `upload`, valid ~27 years) at
  `~/.android-keys/tabscan-upload.jks` by default, outside the repo, and
  writes `tabscan_app/android/key.properties` (git-ignored, mode 600) with
  its path and password. Run again, it prints the key's SHA-1 and SHA-256.
  The keystore and password must be backed up; losing them means asking
  Google to reset the upload key.
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

That's the debug key (today), the upload key (sideloaded release builds)
and Play's app signing key (Play Console → Test and release → App
integrity) once the app is on Play.
