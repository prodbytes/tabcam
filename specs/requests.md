# Request log

Requests that shaped the specification, oldest first. Each entry summarizes
what was asked and what changed. See [README.md](README.md) for the current
spec.

## 2026-10-10

1. **Which OCR library for a Flutter guitar tab scanner?** Recommended
   Google ML Kit text recognition on the device
   (`google_mlkit_text_recognition`), with layout logic of our own on top:
   OCR reads the numbers, but tabs are a grid, so which line a number is on
   and how numbers line up across lines must be worked out separately.
2. **Copy the repository structure of prodbytes/presence, without its app,
   and build a camera app like Adobe Scan or CamScanner for scanning and
   sharing guitar tabs.**
   - Structure, adapted from presence: devbox (Flutter, Python, AWS CLI,
     make, curl), the dev container with its post-create script, the
     `Makefile` and `scripts/` (build, run on web and Android, logs,
     version, RC and GA release tags, deploy, private settings link, health
     monitor), `process-compose.yaml` (web app, index page, health check),
     the Release, Deploy and Deploy RC workflows, `tabscan_infra/` (the
     S3 + CloudFront site and the GitHub OIDC deploy roles),
     `tabscan_index/`, the version files, and this `specs/` folder with
     the CLAUDE.md rules. Left out, as presence's own: the auth API, local
     AWS emulation (Floci), cloud sync, the install script site, and the
     Linux / Raspberry Pi builds. The blank template's PostgreSQL service
     was removed.
   - The app ([tabscan_app/](../tabscan_app)): a [library](library.md) of
     scans, [scanning](scanning.md) with the system document scanner,
     [page filters](page-filters.md), the [scan screen](scan-screen.md),
     [tab recognition](tab-recognition.md) and [sharing](sharing.md).
3. **Fix `devbox services up`, and give this project its own ports
   (not 8080).** It failed because presence's dev stack already held 8080
   and 8081. The web app now serves on **2012** and the index page on
   **2013** (process-compose, the scripts' defaults, the dev container's
   forwarded ports and the docs), so both stacks run side by side.
4. **Create the `tabscan.nu01.com` hosted zone and its delegation, and
   prepare to deploy.** Created the public zone `Z10277161AEN9OU2H73PJ`
   and its NS delegation in `nu01.com` (TTL 3600, like `rbacr` and
   `uplink`); see [deploy](deploy.md). Set the repository variable
   `HOSTED_ZONE_ID`. `TABSCAN_HEALTH_EMAILS` is now read from a repository
   secret, not a variable: the repository is public and run logs show
   variables. Pending: deploying the `tabscan-github-deploy` roles stack,
   then the `AWS_DEPLOY_ROLE_ARN` / `AWS_DEPLOY_RC_ROLE_ARN` variables and
   the `TABSCAN_HEALTH_EMAILS` secret.
5. **One health check line per run, with an icon, short label and status
   for each dependency; print the local URL once at startup.** The
   monitor now prints the app's and the index's URLs when it starts, then
   one line per check (`🏠 index ✅  🎸 web ✅`) instead of a line per
   service. See [development environment](dev-environment.md).
6. **Merge all pending changes and rebuild.** Merged #1 and the health
   check change (as #3: GitHub closed #2 when #1's branch was deleted).
   Rebuilt web, Android and iOS from `main`; the dev stack restarted
   healthy.
7. **Run on the attached iPhone, with the personal team of
   julio@nu01.com.** iOS now signs with the developer's own team from
   `.env` (`IOS_DEVELOPMENT_TEAM`), through a git-ignored xcconfig; see
   [platforms](platforms.md). Installed and launched on the iPhone after
   trusting the developer certificate.
8. **Make a better icon for the app, then relaunch on the iPhone.** New
   [app icon](app-icon.md): a scanned tab page in amber scanner corners,
   generated for Android, iOS and web. Relaunched on the iPhone with it.
