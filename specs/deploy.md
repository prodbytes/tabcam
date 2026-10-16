# Deploy

The web app is served at https://tabcam.nu01.com/app/ (production) and
https://rc.tabcam.nu01.com/app/ (release candidate), from a private S3
bucket behind CloudFront ([tabcam_infra/site.yaml](../tabcam_infra/site.yaml)).
Both names live in the `tabcam.nu01.com` Route 53 zone
(`Z01245733BIHST1A417HE`), delegated from `nu01.com`.
The zone also holds `local.tabcam.nu01.com`, A `127.0.0.1` and AAAA
`::1` (TTL 300), so a name under the real domain reaches the
[local dev servers](dev-environment.md). It was made by hand with the AWS
CLI; no stack owns it.
`/` is the [index page](../tabcam_index), which redirects to `/app/`
(its footer links the privacy policy); `/privacy` is the
[privacy policy](privacy.md).

## The old domains

TabCam was TabScan: `tabscan.nu01.com` and `rc.tabscan.nu01.com` (the
`tabscan-web` and `tabscan-rc-web` stacks, zone `Z10277161AEN9OU2H73PJ`)
are kept as permanent redirects (301) to the same path and query on
`tabcam.nu01.com` and `rc.tabcam.nu01.com` ([site.yaml](../tabcam_infra/site.yaml)
with `RedirectTo`), so links shared before the rename still open, and
still preview as the capture. Deploy them again only to change that.

## Production

A pushed `*GA` tag runs the [Deploy workflow](../.github/workflows/deploy.yml),
which runs `scripts/deploy.sh` for that tag:

1. builds the web app for `/app/` with the tag's version
   (`TABCAM_STAGE=prod`);
2. deploys the `tabcam-web` stack: certificate, bucket, CloudFront and
   DNS records; with `TABCAM_SHARE_API_URL` set, its domain is the stack's
   `ShareApiDomain`, which turns on [link previews](sharing.md#link-previews)
   (the share API as a second origin, for `/preview/*`);
3. uploads `index.html`, the [privacy policy](privacy.md) (as the
   object `privacy`, so it's served at `/privacy`), the web build (`Cache-Control: no-cache`,
   Flutter's files aren't content-hashed) and
   `/.well-known/assetlinks.json` ([App Links](sharing.md#android-app-links)),
   and invalidates `/*`;
   `/status.json` ([maintenance mode](maintenance-mode.md)) is left as
   it is;
4. checks, for up to 10 minutes, that `/app/version.json` reports the
   version, `/` is the index page and `/privacy` the privacy policy.

One production deploy runs at a time; a newer tag waits.

## Release candidates (rc.tabcam.nu01.com)

A pushed `*RC*` tag, or a manual run (with an optional tag; empty deploys
the selected branch's commit), runs the
[Deploy RC workflow](../.github/workflows/deploy-rc.yml): the same script
with `STAGE=rc`, into its own stack, `tabcam-rc-web`. The RC's title is
"🧪 TabCam RC" in the browser and the app, so it never passes for
production.

## Access

AWS access is keyless: GitHub's OIDC token is exchanged for
`tabcam-github-deploy` (only `*GA` tags) or `tabcam-github-deploy-rc`
(`*RC*` tags and manual runs from `main`, only `tabcam-rc-*` resources and
`rc.tabcam.nu01.com` records) ([tabcam_infra/github-deploy.yaml](../tabcam_infra/github-deploy.yaml)).
Repository variables: `TABCAM_AWS_DEPLOY_ROLE_ARN`, `TABCAM_AWS_DEPLOY_RC_ROLE_ARN`,
`TABCAM_HOSTED_ZONE_ID`, and for [sign-in and cloud sync](cloud-sync.md)
`TABCAM_GOOGLE_WEB_CLIENT_ID`, `TABCAM_GOOGLE_IOS_CLIENT_ID` (releases only),
`TABCAM_COGNITO_IDENTITY_POOL_ID`, `TABCAM_USER_DATA_BUCKET` and (for
[shared captures](shared-captures.md)) `TABCAM_SHARE_API_URL` and (for
[TabCam Premium](cloud-ocr.md)) `TABCAM_OCR_URL`, compiled into
the builds (empty: no sign-in, no sharing, or no Premium). Their stacks,
`tabcam-user-data`, `tabcam-identity`, `tabcam-share-api`,
`tabcam-ocr-repo` and `tabcam-ocr`, are
deployed by an administrator, not by the workflows. Every stack carries the
cost-allocation tags `project=tabcam` and `tenancy` (`GA`, `RC`, or `shared`
for the stacks both stages use; see [tabcam_infra/README.md](../tabcam_infra/README.md)). One-time setup:
[tabcam_infra/README.md](../tabcam_infra/README.md).

Uptime isn't watched by these stacks: the `nu01-monitor` stack (in the nu01
repository) fetches https://tabcam.nu01.com/app/version.json and the RC's
every 5 minutes and emails when one fails. It replaced the sites' Route 53
health checks, alarms and SNS topics (removed 2026-10-14, to save their
cost); the deploy roles keep the permissions to delete those until the
next GA deploy has.

By hand, with admin credentials: `TAG=0.1.<Z>-GA bash scripts/deploy.sh`
(`STAGE=rc` for the RC; `SKIP_BUILD=1` to reuse a build).
