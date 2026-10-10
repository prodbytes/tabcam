# Release builds

[.github/workflows/release.yml](../.github/workflows/release.yml) builds the
app binaries with `make` and publishes them as a GitHub release.

- **Triggers:**
  - A pushed tag matching `*QA` or `*RC*` (e.g. `0.1.202610101200-RC`) is
    released as a **prerelease**. `*RC*` tags are also
    [deployed](deploy.md) to https://rc.tabscan.nu01.com.
  - A pushed tag matching `*GA` is released as a full release (GitHub's
    latest) and [deployed](deploy.md) to https://tabscan.nu01.com.
  - **Manual dispatch** takes an optional `tag` (created on the dispatched
    commit if missing; empty uses the selected tag, or `manual-<run>`) and
    a `prerelease` switch (on by default).
  - **Pull requests** that change the workflow, the `Makefile`,
    `scripts/make.sh`, `scripts/dart-defines.sh`, `scripts/version.sh` or
    the version files only build, without a release.
  - Tag names must be letters, digits, `.`, `_` and `-`.
- **Builds**, one job per target, with Flutter 3.47.5 (cloned at its tag):
  `web` and `android` (JDK 17) on `ubuntu-latest`, `ios` on
  `macos-latest`. Each runs `make <target>`.
- **Release** `tabscan-<tag>`, with generated notes and:
  - `tabscan-<tag>-web.zip`: the web build;
  - `tabscan-<tag>-android.apk`: the release APK (signed with the debug
    key until a release key is set up; that key is new each run, so its
    [App Links](sharing.md#android-app-links) aren't verified);
  - `tabscan-<tag>-ios-unsigned.zip`: the unsigned `Runner.app`.
- **Security**: actions are pinned to commit SHAs; the token is read-only
  except in the release job (`contents: write`); checkout doesn't keep
  credentials; no secrets are used.

## Versioning

The version is `X.Y.Z`: X and Y from [version.X.txt](../version.X.txt) and
[version.Y.txt](../version.Y.txt) (now 0.1), Z the build time as
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

`make` builds every platform this host can; `make web|android|ios` one
(`scripts/make.sh`). `MODE=release|profile|debug` (release by default),
`IOS_CODESIGN=1` signs iOS, `WEB_BASE_HREF` sets the web base (`/app/` for
the site). `make clean` runs `flutter clean`.
