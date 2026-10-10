# Deploy

The web app is served at https://tabscan.nu01.com/app/ (production) and
https://rc.tabscan.nu01.com/app/ (release candidate), from a private S3
bucket behind CloudFront ([tabscan_infra/site.yaml](../tabscan_infra/site.yaml)).
Both names live in the `tabscan.nu01.com` Route 53 zone
(`Z10277161AEN9OU2H73PJ`), delegated from `nu01.com`.
The zone also holds `local.tabscan.nu01.com`, A `127.0.0.1` and AAAA
`::1` (TTL 300), so a name under the real domain reaches the
[local dev servers](dev-environment.md). It was made by hand with the AWS
CLI; no stack owns it.
`/` is the [index page](../tabscan_index), which redirects to `/app/`.

## Production

A pushed `*GA` tag runs the [Deploy workflow](../.github/workflows/deploy.yml),
which runs `scripts/deploy.sh` for that tag:

1. builds the web app for `/app/` with the tag's version
   (`TABSCANNER_STAGE=prod`);
2. deploys the `tabscan-web` stack: certificate, bucket, CloudFront, DNS
   records, and a Route 53 health check of `/app/version.json` (it must
   name `tabscan_app`) whose alarm emails `TABSCANNER_HEALTH_EMAILS`;
3. uploads `index.html` and the web build (`Cache-Control: no-cache`,
   Flutter's files aren't content-hashed) and invalidates `/*`;
   `/status.json` ([maintenance mode](maintenance-mode.md)) is left as
   it is;
4. checks, for up to 10 minutes, that `/app/version.json` reports the
   version and `/` is the index page.

One production deploy runs at a time; a newer tag waits.

## Release candidates (rc.tabscan.nu01.com)

A pushed `*RC*` tag, or a manual run (with an optional tag; empty deploys
the selected branch's commit), runs the
[Deploy RC workflow](../.github/workflows/deploy-rc.yml): the same script
with `STAGE=rc`, into its own stack, `tabscan-rc-web`. The RC's title is
"🧪 TabScan RC" in the browser and the app, so it never passes for
production.

## Access

AWS access is keyless: GitHub's OIDC token is exchanged for
`tabscan-github-deploy` (only `*GA` tags) or `tabscan-github-deploy-rc`
(`*RC*` tags and manual runs from `main`, only `tabscan-rc-*` resources and
`rc.tabscan.nu01.com` records) ([tabscan_infra/github-deploy.yaml](../tabscan_infra/github-deploy.yaml)).
Repository variables: `TABSCANNER_AWS_DEPLOY_ROLE_ARN`, `TABSCANNER_AWS_DEPLOY_RC_ROLE_ARN`,
`TABSCANNER_HOSTED_ZONE_ID`, and for [sign-in and cloud sync](cloud-sync.md)
`TABSCANNER_GOOGLE_WEB_CLIENT_ID`, `TABSCANNER_GOOGLE_IOS_CLIENT_ID` (releases only),
`TABSCANNER_COGNITO_IDENTITY_POOL_ID`, `TABSCANNER_USER_DATA_BUCKET` and (for
[shared captures](shared-captures.md)) `TABSCANNER_SHARE_API_URL` and (for
[TabScan Premium](cloud-ocr.md)) `TABSCANNER_OCR_URL`, compiled into
the builds (empty: no sign-in, no sharing, or no Premium). Their stacks,
`tabscan-user-data`, `tabscan-identity`, `tabscan-share-api`,
`tabscan-ocr-repo` and `tabscan-ocr`, are
deployed by an administrator, not by the workflows; repository secret: `TABSCANNER_HEALTH_EMAILS` (a secret
because the repository is public and run logs show variables). One-time setup:
[tabscan_infra/README.md](../tabscan_infra/README.md).

By hand, with admin credentials: `TAG=0.1.<Z>-GA bash scripts/deploy.sh`
(`STAGE=rc` for the RC; `SKIP_BUILD=1` to reuse a build).
