# TabScan

Scan guitar tabs with your phone's camera, read them as text, and share
them: like a document scanner app, made for tablature.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://codespaces.new/prodbytes/tabscan)

- **Scan**: the system document scanner finds the page, straightens it and
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
| [tabscan_app/](tabscan_app) | The Flutter app (Android, iOS, web) |
| [tabscan_index/](tabscan_index) | The site root page, which redirects to `/app/` |
| [tabscan_infra/](tabscan_infra) | CloudFormation: the site (S3 + CloudFront) and the GitHub deploy roles |
| [scripts/](scripts) | Build, run, release and deploy scripts |
| [specs/](specs) | The specification, one file per feature, and the request log |
| [.github/workflows/](.github/workflows) | Release (binaries), Deploy (GA) and Deploy RC |

## Getting started

Click the Codespaces badge, or locally:

```bash
git clone git@github.com:prodbytes/tabscan.git
code tabscan   # then "Reopen in Container" when prompted
```

Inside the container (or any machine with [Devbox](https://www.jetify.com/devbox)):

```bash
devbox shell              # enter the environment
devbox services up        # web app on http://localhost:2012/app/, index on :2013
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
- `5-index`: the site root ([tabscan_index/](tabscan_index));
- `0-health-check`: once both are ready, one status line per service every
  15 s (`HEALTH_CHECK_INTERVAL`):

```
2026-10-10 14:02:10 🏠 index ✅     localhost:2013/
2026-10-10 14:02:10 🎸 web   ✅     localhost:2012/app/
```

Stop everything with `devbox services stop`.

## Releases

`bash scripts/release-rc.sh` tags the current commit `X.Y.Z-RC` and
`bash scripts/release-ga.sh` tags `X.Y.Z-GA` (X and Y from
[version.X.txt](version.X.txt) and [version.Y.txt](version.Y.txt), Z the
time). Tags start the [Release](.github/workflows/release.yml) workflow
(APK, unsigned iOS app, web zip) and deploy the web app: RC tags to
https://rc.tabscan.nu01.com, GA tags to https://tabscan.nu01.com. See
[specs/release.md](specs/release.md) and [specs/deploy.md](specs/deploy.md).

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
