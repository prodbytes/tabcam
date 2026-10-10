# Development environment

- **Toolchain**: [devbox.json](../devbox.json), locked in `devbox.lock`:
  Flutter, Python (the index server, the deploy script), the AWS CLI, GNU
  make, curl, and mkcert and openssl (the local HTTPS certificate). `devbox shell` enters it.
- **Dev container** ([.devcontainer/](../.devcontainer)): Ubuntu 24.04 with
  Devbox 0.18.1 and Nix 2.35.0 (single-user, installer hash-checked);
  `post-create.sh` fetches the locked Nix store paths from
  `cache.nixos.org`, then runs `devbox install`, handing Codespaces'
  `GITHUB_TOKEN` to Nix against GitHub API rate limits. Docker-in-Docker,
  the Dart, Flutter, Python, Docker and YAML extensions, and ports 2012,
  2013, 2014 and 2443 forwarded. It sets `TABSCANNER_BIND_HOST=0.0.0.0`, so
  that Floci, inside docker-in-docker, can reach the dev servers. Codespaces ask for 4 CPUs and 8 GB.
- **Services** (`devbox services up`, [process-compose.yaml](../process-compose.yaml)):
  - `2-flutter-web`: the app on http://localhost:2012/app/ (the `/app/`
    base href production uses), on Flutter's `web-server` device, through
    `scripts/flutter-web.sh` (also `devbox run web`). Ready when `/app/`
    answers. Stopping it also stops whatever listens on the port.
  - `5-index`: [tabscan_index/site](../tabscan_index) on
    http://localhost:2013/.
  - `4-floci`: [Floci](https://floci.io/), a local AWS emulator, as the
    CloudFront distribution in front of both, as deployed: `/app*` goes to
    the app and everything else to the index
    ([tabscan_floci/](../tabscan_floci/README.md)). It serves HTTP on
    http://tabscan.localhost:2014/ (`FLOCI_PORT`) and HTTPS on
    https://local.tabscan.nu01.com:2443/ (`FLOCI_HTTPS_PORT`). The
    certificate comes from mkcert (`scripts/local-certs.sh`, run before
    Floci starts) and covers `local.tabscan.nu01.com`, `tabscan.localhost`,
    `*.tabscan.localhost`, `localhost`, `127.0.0.1` and `::1`. It is kept
    in the git-ignored `tabscan_floci/certs/`. Browsers trust it after a
    one-time `devbox run mkcert -install`. Floci keeps nothing between
    starts, and hot reload works through it.
  - `0-health-check`: once all are ready, it prints the local URLs once
    (🎸 the app, 🏠 the index, 🔒 HTTPS), then every 15 s
    (`HEALTH_CHECK_INTERVAL`) one line for the whole check: the time, then
    each dependency as its icon, a short label and ✅ or ❌, e.g.
    `2026-10-10 14:02:10  🏠 index ✅  🎸 web ✅  🚚 cdn ✅  🔒 https ✅`.
    `cdn` asks Floci for `/app/` by its alias. `https` fetches
    https://local.tabscan.nu01.com:2443/app/ and validates the certificate
    against mkcert's CA.
  - Servers bind to 127.0.0.1; `TABSCANNER_BIND_HOST=0.0.0.0` serves other
    devices (a phone's browser).
  - `local.tabscan.nu01.com` resolves to localhost (`127.0.0.1`, `::1`),
    so the local app is reachable under the real domain, over HTTPS through
    Floci: https://local.tabscan.nu01.com:2443/app/.
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
  `TABSCANNER_USER_DATA_BUCKET`, `TABSCANNER_SHARE_API_URL`, for
  [TabScan Premium](cloud-ocr.md) `TABSCANNER_OCR_URL`, and
  [maintenance mode](maintenance-mode.md)'s `TABSCANNER_STATUS_URL`, all public
  identifiers); the version is passed as `TABSCANNER_VERSION`. The
  environment wins over `.env`.
- **Local web sign-in**: the dev web server (`scripts/flutter-web.sh`)
  passes `TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID`, when set, as
  `TABSCANNER_GOOGLE_WEB_CLIENT_ID`. That is the "local - web" OAuth client,
  `1061413485511-2ndd6lqkmi61j17vpk5f2ntjb91tt38r`. Its authorized
  JavaScript origins must list each local URL with its port:
  `https://local.tabscan.nu01.com:2443` and `http://localhost:2012`. The web
  button needs no redirect URI. `TABSCANNER_GOOGLE_WEB_CLIENT_ID` stays the
  production client, because manual deploys read it from `.env`. A
  Cognito pool trusts one Google client, so the local client has its own
  pool, `tabscan-local` (stack `tabscan-identity-local`): with
  `TABSCANNER_COGNITO_LOCAL_IDENTITY_POOL_ID` set, the dev web server
  passes it as `TABSCANNER_COGNITO_IDENTITY_POOL_ID` along with the local
  client (without it, it warns that the pool will refuse the local
  client's tokens). Local identities are not the production ones, so a
  local build syncs to its own folder in the bucket. Premium and sharing don't work in local web builds: the OCR service and the share API accept the local client's tokens but look the identity up in the main pool, which refuses them.
- **Setting names**: every TabScan setting is prefixed `TABSCANNER_`, and
  keeps the same name in `.env`, the scripts, the app's dart-defines and
  the GitHub repository variables and secrets. `AWS_REGION` keeps its
  standard name, as the AWS CLI reads it.
- **Checks**: `flutter analyze` and `flutter test` in `tabscan_app/`;
  the share API's tests with `python3 -m unittest discover -s
  tabscan_api/shares`; the cloud OCR service's `pytest` and image build
  ([tabscan_locr/](../tabscan_locr/README.md#test)).
  Tests use made-up riffs, never tabs of published songs.
