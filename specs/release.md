# Release builds

[.github/workflows/release.yml](../.github/workflows/release.yml) builds the
app binaries with `make` and publishes them as a GitHub release.

- **Triggers:**
  - A pushed tag matching `*QA` or `*RC*` (e.g. `0.2.202610101200-RC`) is
    released as a **prerelease**. `*RC*` tags are also
    [deployed](deploy.md) to https://rc.tabcam.nu01.com.
  - A pushed tag matching `*GA` is released as a full release (GitHub's
    latest) and [deployed](deploy.md) to https://tabcam.nu01.com.
  - **Manual dispatch** takes an optional `tag` (created on the dispatched
    commit if missing; empty uses the selected tag, or `manual-<run>`) and
    a `prerelease` switch (on by default).
  - **Pull requests** that change the workflow, the `Makefile`,
    `scripts/make.sh`, `scripts/dart-defines.sh`, `scripts/version.sh` or
    the version files only build, without a release.
  - Tag names must be letters, digits, `.`, `_` and `-`.
- **Builds**, one job per target, with Flutter 3.47.5 (cloned at its tag):
  `web` and `android` (JDK 17) on `ubuntu-latest`, `ios` on
  `macos-latest`. Each runs `make <target>`; Android runs
  `make android appbundle`.
- **Android signing**: on tags and manual runs, with the upload key from
  the secrets `ANDROID_UPLOAD_KEYSTORE_BASE64` and
  `ANDROID_UPLOAD_KEYSTORE_PASSWORD` ([app stores](app-stores.md#android-signing)),
  written to `key.properties` on the runner and removed after the build.
  Without them (and always on pull requests), a debug key new each run.
- **Release** `tabcam-<tag>`, with generated notes and:
  - `tabcam-<tag>-web.zip`: the web build;
  - `tabcam-<tag>-android.apk`: the release APK, and
    `tabcam-<tag>-android.aab`: the App Bundle for Google Play, both
    signed as above (with a debug key, their
    [App Links](sharing.md#android-app-links) aren't verified);
  - `tabcam-<tag>-ios-unsigned.zip`: the unsigned `Runner.app`.
- **Security**: actions are pinned to commit SHAs; the token is read-only
  except in the release job (`contents: write`); checkout doesn't keep
  credentials; the only secrets are the Android upload key's, given to
  the Android build step that needs them, never on pull requests.

## Installing a release

The [README](../README.md#installing-a-release-on-a-phone) says how
testers install a release on a phone until the app is in the stores:

- **Android**: the release's APK, opened on the phone or installed with
  `adb install -r`. It installs over earlier releases, but over a build
  signed with another key only after uninstalling that build. Google
  sign-in in it waits for the upload key's OAuth client
  ([app stores](app-stores.md#android-signing)).
- **iOS**: the release's app is unsigned, so the release's tag is built
  and installed with the tester's own team (`scripts/flutter-run.sh
  --release --no-resident`, [platforms](platforms.md)). A free team's
  build lasts 7 days.

## Versioning

The version is `X.Y.Z`: X and Y from [version.X.txt](../version.X.txt) and
[version.Y.txt](../version.Y.txt) (now 0.2), Z the build time as
`YYYYMMDDHHMM` (UTC). The build number (Android's versionCode, iOS's
CFBundleVersion) is the same time in Unix seconds. `scripts/version.sh`
works these out; `VERSION_Z` and `BUILD_NUMBER` override them. A tag that
carries `X.Y.Z` keeps its Z for the build, and fails if its X.Y doesn't
match the version files. The app shows the version in About.

## Cutting a release

- `bash scripts/release-rc.sh` tags the current commit `X.Y.Z-RC` and
  pushes the tag.
- `bash scripts/release-ga.sh` tags `X.Y.Z-GA`; the commit must be on
  `main`.

Both refuse uncommitted changes, an unpushed commit, or a tag that exists
already; `DRY_RUN=1` only prints the tag.

## Make

`make` builds every platform this host can; `make web|android|ios` one,
`make appbundle` the Android App Bundle, `make ipa` the signed App Store
build ([app stores](app-stores.md#ios-distribution)) (`scripts/make.sh`). `MODE=release|profile|debug` (release by default),
`IOS_CODESIGN=1` signs iOS, `WEB_BASE_HREF` sets the web base (`/app/` for
the site). `make clean` runs `flutter clean`.
