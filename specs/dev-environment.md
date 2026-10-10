# Development environment

- **Toolchain**: [devbox.json](../devbox.json), locked in `devbox.lock`:
  Flutter, Python (the index server, the deploy script), the AWS CLI, GNU
  make and curl. `devbox shell` enters it.
- **Dev container** ([.devcontainer/](../.devcontainer)): Ubuntu 24.04 with
  Devbox 0.18.1 and Nix 2.35.0 (single-user, installer hash-checked);
  `post-create.sh` fetches the locked Nix store paths from
  `cache.nixos.org`, then runs `devbox install`, handing Codespaces'
  `GITHUB_TOKEN` to Nix against GitHub API rate limits. Docker-in-Docker,
  the Dart, Flutter, Python, Docker and YAML extensions, and ports 2012 and
  2013 forwarded. Codespaces ask for 4 CPUs and 8 GB.
- **Services** (`devbox services up`, [process-compose.yaml](../process-compose.yaml)):
  - `2-flutter-web`: the app on http://localhost:2012/app/ (the `/app/`
    base href production uses), on Flutter's `web-server` device, through
    `scripts/flutter-web.sh` (also `devbox run web`). Ready when `/app/`
    answers. Stopping it also stops whatever listens on the port.
  - `5-index`: [tabscan_index/site](../tabscan_index) on
    http://localhost:2013/.
  - `0-health-check`: once both are ready, it prints the local URLs once
    (🎸 the app, 🏠 the index), then every 15 s (`HEALTH_CHECK_INTERVAL`)
    one line for the whole check: the time, then each dependency as its
    icon, a short label and ✅ or ❌, e.g.
    `2026-10-10 14:02:10  🏠 index ✅  🎸 web ✅`.
  - Servers bind to 127.0.0.1; `TABSCANNER_BIND_HOST=0.0.0.0` serves other
    devices (a phone's browser).
- **Android** (USB, debugging on; `ANDROID_SERIAL` picks one of several):
  `devbox run android` runs a debug build attached
  (`scripts/flutter-android.sh`); `devbox run android-release` installs a
  release build over the app (keeping its events), starts it and checks it
  runs (`scripts/android-install.sh`); `devbox run android-log` streams the
  app's log lines and the system's related errors
  (`scripts/android-log.sh`, `--clear`, `--all`).
- **Any device**: `bash scripts/flutter-run.sh -d <device>`.
- **Settings**: `.env` (git-ignored; see [.env.example](../.env.example)),
  linked from the private `prodbytes/setec-astronomy` repo
  (`tabscan.nu01/`) by `scripts/link-private.sh`. Only names listed in
  `scripts/dart-defines.sh` reach the app (`TABSCANNER_STAGE`, and for
  [sign-in and cloud sync](cloud-sync.md)
  `TABSCANNER_GOOGLE_WEB_CLIENT_ID`, `TABSCANNER_GOOGLE_IOS_CLIENT_ID`,
  `AWS_REGION`, `TABSCANNER_COGNITO_IDENTITY_POOL_ID`,
  `TABSCANNER_USER_DATA_BUCKET`, `TABSCANNER_SHARE_API_URL` and, for
  [TabScan Premium](cloud-ocr.md), `TABSCANNER_OCR_URL`, all public
  identifiers); the version is passed as `TABSCANNER_VERSION`. The
  environment wins over `.env`.
- **Setting names**: every TabScan setting is prefixed `TABSCANNER_`, and
  keeps the same name in `.env`, the scripts, the app's dart-defines and
  the GitHub repository variables and secrets. `AWS_REGION` keeps its
  standard name, as the AWS CLI reads it.
- **Checks**: `flutter analyze` and `flutter test` in `tabscan_app/`;
  the share API's tests with `python3 -m unittest discover -s
  tabscan_api/shares`; the cloud OCR service's `pytest` and image build
  ([tabscan_locr/](../tabscan_locr/README.md#test)).
  Tests use made-up riffs, never tabs of published songs.
