# Deploy

The web app is served at https://tabscan.nu01.com/app/ (production) and
https://rc.tabscan.nu01.com/app/ (release candidate), from a private S3
bucket behind CloudFront ([tabscan_infra/site.yaml](../tabscan_infra/site.yaml)).
Both names live in the apex Route 53 zone `nu01.com`
(`Z04838091YTBIM6PNI1XK`), which the **nu01 repository** manages: the zone
is its `nu01-route53-zone` stack, and its `nu01-dns` stack owns the A/AAAA
aliases of `tabscan.nu01.com` and `rc.tabscan.nu01.com` and
`local.tabscan.nu01.com` (A `127.0.0.1` and AAAA `::1`, so a name under the
real domain reaches the [local dev servers](dev-environment.md)). This
repository's stacks hold no DNS records; they only validate their ACM
certificates in `nu01.com`
([tabscan_infra/README.md](../tabscan_infra/README.md#dns)).

`tabscan.nu01.com` used to have its own zone, `Z10277161AEN9OU2H73PJ`,
delegated from `nu01.com`; it was merged into `nu01.com` (2026-10-14) in
two rounds. Round 1, in the nu01 repository, removed the delegation and
moved the records; round 2, this repository's change, moved certificate
validation to `nu01.com` and dropped the site stacks' records, and must
not be released sooner than 48 hours after round 1 (the nu01 repository's
`migrate-subzone.sh` prints the time): until then resolvers may still
follow the old delegation and the new certificates can't validate. The
deploy roles must be updated before that release, and the old zone is
deleted once it has deployed on both stages
([the procedure](../tabscan_infra/README.md#the-zone-merge-2026-10-14)).
`/` is the [index page](../tabscan_index), which redirects to `/app/`
(its footer links the privacy policy); `/privacy` is the
[privacy policy](privacy.md).

## Production

A pushed `*GA` tag runs the [Deploy workflow](../.github/workflows/deploy.yml),
which runs `scripts/deploy.sh` for that tag:

1. builds the web app for `/app/` with the tag's version
   (`TABSCANNER_STAGE=prod`);
2. deploys the `tabscan-web` stack: certificate (validated in
   `nu01.com`), bucket and CloudFront; with `TABSCANNER_SHARE_API_URL` set, its domain is the stack's
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
(`*RC*` tags and manual runs from `main`, only `tabscan-rc-*` resources)
([tabscan_infra/github-deploy.yaml](../tabscan_infra/github-deploy.yaml)).
In `nu01.com` each role may only change its stage's certificate validation
names (`_*.tabscan.nu01.com`, or `_*.rc.tabscan.nu01.com` for the RC);
until the zone merge is done they also keep their old records in the old
`tabscan.nu01.com` zone, so the first deploys after it can delete them.
Repository variables: `TABSCANNER_AWS_DEPLOY_ROLE_ARN`, `TABSCANNER_AWS_DEPLOY_RC_ROLE_ARN`,
and for [sign-in and cloud sync](cloud-sync.md)
`TABSCANNER_GOOGLE_WEB_CLIENT_ID`, `TABSCANNER_GOOGLE_IOS_CLIENT_ID` (releases only),
`TABSCANNER_COGNITO_IDENTITY_POOL_ID`, `TABSCANNER_USER_DATA_BUCKET` and (for
[shared captures](shared-captures.md)) `TABSCANNER_SHARE_API_URL` and (for
[TabScan Premium](cloud-ocr.md)) `TABSCANNER_OCR_URL`, compiled into
the builds (empty: no sign-in, no sharing, or no Premium). Their stacks,
`tabscan-user-data`, `tabscan-identity`, `tabscan-share-api`,
`tabscan-ocr-repo` and `tabscan-ocr`, are
deployed by an administrator, not by the workflows. Every stack carries the
cost-allocation tags `project=tabscan` and `tenancy` (`GA`, `RC`, or `shared`
for the stacks both stages use; see [tabscan_infra/README.md](../tabscan_infra/README.md)). One-time setup:
[tabscan_infra/README.md](../tabscan_infra/README.md).

Uptime isn't watched by these stacks: the `nu01-monitor` stack (in the nu01
repository) fetches https://tabscan.nu01.com/app/version.json and the RC's
every 5 minutes and emails when one fails. It replaced the sites' Route 53
health checks, alarms and SNS topics (removed 2026-10-14, to save their
cost); the deploy roles keep the permissions to delete those until the
next GA deploy has.

By hand, with admin credentials: `TAG=0.1.<Z>-GA bash scripts/deploy.sh`
(`STAGE=rc` for the RC; `SKIP_BUILD=1` to reuse a build).
