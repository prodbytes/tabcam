# TabCam

Scan guitar tabs with your phone's camera, read them as text, and share
them: like a document camera app, made for tablature.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/prodbytes/tabcam)

- **Scan**: the system document camera finds the page, straightens it and
  takes several pages in a row (Android: ML Kit; iOS: VisionKit).
- **Clean up**: the Tab filter turns each page into crisp black ink on
  white, without shadows or paper tint.
- **Read tab**: on-device OCR turns the pages into editable plain-text tab,
  from printed text tabs or typeset tab staves.
- **Share**: as a PDF, as text, or as images.

What the app does is specified in [specs/](specs/README.md).

## Layout

| Path | Holds |
|---|---|
| [tabcam_app/](tabcam_app) | The Flutter app (Android, iOS, web) |
| [tabcam_index/](tabcam_index) | The site root page, which redirects to `/app/` |
| [tabcam_infra/](tabcam_infra) | CloudFormation: the site (S3 + CloudFront) and the GitHub deploy roles |
| [scripts/](scripts) | Build, run, release and deploy scripts |
| [specs/](specs) | The specification, one file per feature, and the request log |
| [.github/workflows/](.github/workflows) | Release (binaries), Deploy (GA) and Deploy RC |

## Getting started

Click the Codespaces badge, or locally:

```bash
git clone git@github.com:prodbytes/tabcam.git
code tabcam   # then "Reopen in Container" when prompted
```

Inside the container (or any machine with [Devbox](https://www.jetify.com/devbox)):

```bash
devbox shell              # enter the environment
devbox services up        # web app on http://localhost:2012/app/, index on :2013,
                          # HTTPS on https://local.tabcam.nu01.com:2443/app/
devbox run android        # run on the Android phone attached by USB
make                      # build every platform this host can (see the Makefile)
```

Scanning with edge detection and Read tab need the Android or iOS app; the
web app takes plain photos (see [specs/platforms.md](specs/platforms.md)).

Private settings (deploy targets) live in the private
`prodbytes/setec-astronomy` repo; `bash scripts/link-private.sh` links its
`.env` in. See [.env.example](.env.example).

## Services

`devbox services up` starts, through [process-compose.yaml](process-compose.yaml):

- `2-flutter-web`: the app in web mode ([scripts/flutter-web.sh](scripts/flutter-web.sh));
- `4-floci`: [Floci](https://floci.io/), a local AWS emulator, as the
  CloudFront distribution in front of both, over HTTP and HTTPS
  ([tabcam_floci/](tabcam_floci/README.md));
- `5-index`: the site root ([tabcam_index/](tabcam_index));
- `0-health-check`: once all are ready, prints the local URLs once, then
  one line per check every 15 s (`HEALTH_CHECK_INTERVAL`), each dependency
  with its icon, label and status:

```
🎸 TabCam: http://localhost:2012/app/
🏠 index:   http://localhost:2013/ (redirects to the app)
🔒 HTTPS:   https://local.tabcam.nu01.com:2443/app/ (through Floci's CloudFront)
2026-10-10 14:02:10  🏠 index ✅  🎸 web ✅  🚚 cdn ✅  🔒 https ✅
```

Stop everything with `devbox services stop`.

`local.tabcam.nu01.com` resolves to 127.0.0.1. The certificate is signed by
mkcert's local CA. To have browsers trust it, run this once:
`devbox run mkcert -install`. It asks for your password.

## Releases

`bash scripts/release-rc.sh` tags the current commit `X.Y.Z-RC` and
`bash scripts/release-ga.sh` tags `X.Y.Z-GA` (X and Y from
[version.X.txt](version.X.txt) and [version.Y.txt](version.Y.txt), Z the
time). Tags start the [Release](.github/workflows/release.yml) workflow
(APK, unsigned iOS app, web zip) and deploy the web app: RC tags to
https://rc.tabcam.nu01.com, GA tags to https://tabcam.nu01.com. See
[specs/release.md](specs/release.md) and [specs/deploy.md](specs/deploy.md).

## Installing a release on a phone

Each release on the
[Releases page](https://github.com/prodbytes/tabcam/releases) has the
app files: **Latest** is the GA release and **Pre-release** is an RC.
Until the app is in the stores, install it like this.

### Android

The release's `tabcam-<tag>-android.apk` is signed with the upload key.
It installs over an earlier release and keeps your events.

- **On the phone:** download the APK from the release in the phone's
  browser and open it. The first time, Android asks you to allow
  installing apps from that browser (Settings → Apps → Special app access
  → Install unknown apps). Then tap **Install**, or **Update** if TabCam
  is already installed.
- **From a computer**, with the phone connected by USB and USB debugging
  on (Settings → Developer options):

  ```bash
  gh release download <tag> --repo prodbytes/tabcam --pattern '*-android.apk'
  adb install -r tabcam-<tag>-android.apk
  ```

  Leave out `<tag>` to download the latest release.

If Android says the app conflicts with an installed one
(`INSTALL_FAILED_UPDATE_INCOMPATIBLE` from `adb`), the installed TabCam
was signed with another key, for example a `flutter run` debug build.
Sign in and let it sync first, then uninstall it and install the
release. Uninstalling deletes the events that are only on the phone.

Google sign-in in a release APK needs the upload key's OAuth client,
which isn't set up yet ([specs/app-stores.md](specs/app-stores.md)).
Until it is, release builds can capture but not sign in.

### iOS

An iPhone only installs signed apps, and the release's
`tabcam-<tag>-ios-unsigned.zip` isn't signed. Instead, build that
release's commit on a Mac and install it with your own Apple team. A
free Personal Team works.

1. Once: set `TABCAM_IOS_DEVELOPMENT_TEAM` in `.env` to your team ID
   (Xcode → Settings → Accounts). Connect the iPhone by USB, trust the
   Mac, and turn on Developer Mode on the iPhone (Settings → Privacy &
   Security → Developer Mode). The iPhone restarts.
2. Build and install the release:

   ```bash
   git fetch --tags && git checkout <tag>     # e.g. 0.1.202610111144-GA
   flutter devices                            # the iPhone's ID
   TABCAM_OCR_URL="$(gh variable get TABCAM_OCR_URL)" \
     bash scripts/flutter-run.sh -d <iPhone ID> --release --no-resident
   ```

   This builds a release build, signs it with your team, installs it over
   the current app (keeping your events) and starts it.
   `TABCAM_OCR_URL` gives the build the Premium service that the
   published builds use (Premium and Fix). Your `.env` has the rest.
3. The first time, iOS won't open an app from a new developer. Trust it
   in Settings → General → VPN & Device Management.

With a free Personal Team, the app stops opening after 7 days: install it
again. A paid team's builds last a year. Once the app is on TestFlight,
testers install it from there instead
([specs/app-stores.md](specs/app-stores.md)).

## How the container is built

The [Containerfile](.devcontainer/Containerfile) keeps the Microsoft
`ubuntu-24.04` devcontainer base image and layers Devbox on top:

1. Devbox (pinned) is installed as root, then everything else runs as the
   `vscode` user so the Nix store ownership matches the container's
   `remoteUser`.
2. Nix (a pinned release, its installer checked against a hash) is
   installed in single-user mode (`--no-daemon`): containers have no
   systemd, so the multi-user Nix daemon can't run.
3. After the container is created,
   [post-create.sh](.devcontainer/post-create.sh) fetches the locked store
   paths straight from `cache.nixos.org`, then runs `devbox install`. It
   hands Codespaces' `GITHUB_TOKEN` to Nix, so GitHub API rate limits don't
   break it.
