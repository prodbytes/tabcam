# tabscan_infra

The production (and release-candidate) infrastructure, as CloudFormation
templates.

| Template | Stack | Holds |
|---|---|---|
| [site.yaml](site.yaml) | `tabscan-web` | https://tabscan.nu01.com: the ACM certificate (DNS-validated in the `tabscan.nu01.com` zone), a private S3 bucket, a CloudFront distribution, the Route 53 A/AAAA aliases, and a Route 53 health check of `/app/version.json` that emails `TABSCAN_HEALTH_EMAILS` when it fails |
| [github-deploy.yaml](github-deploy.yaml) | `tabscan-github-deploy` | The `tabscan-github-deploy` role (Deploy workflow, `*GA` tags) and the `tabscan-github-deploy-rc` role (Deploy RC workflow: `*RC*` tags and manual runs from `main`, limited to `tabscan-rc-*` resources and the `rc.tabscan.nu01.com` records), trusting GitHub's OIDC provider |

`scripts/deploy.sh` deploys `tabscan-web`. With `STAGE=rc` it deploys the
release candidate's own copy, `tabscan-rc-web`, for
https://rc.tabscan.nu01.com; `*RC*` tags do that through
[deploy-rc.yml](../.github/workflows/deploy-rc.yml).

## The distribution

| Path | Origin |
|---|---|
| default (`/`) | S3 `index.html`, the [index page](../tabscan_index) that redirects to `/app/` |
| `/app*` | S3 `app/`, the Flutter web build (`--base-href /app/`). A CloudFront Function redirects `/app` to `/app/` and maps directory URIs to `index.html` |

Every file is uploaded with `Cache-Control: no-cache`, because Flutter's web
files aren't content-hashed. Each deploy also invalidates `/*`.

## Deploying

Push a GA tag (`bash scripts/release-ga.sh`). The
[Deploy workflow](../.github/workflows/deploy.yml) then runs
[scripts/deploy.sh](../scripts/deploy.sh), which:

1. builds the web app for `/app/`;
2. deploys `site.yaml`;
3. uploads the content and invalidates the cache;
4. checks that `https://tabscan.nu01.com/app/version.json` reports the
   tag's version.

`scripts/deploy.sh` also runs by hand with admin credentials (inside
devbox): `TAG=0.1.<Z>-GA bash scripts/deploy.sh`.

## DNS

`tabscan.nu01.com` has its own public Route 53 zone,
`Z10277161AEN9OU2H73PJ` (`HOSTED_ZONE_ID`), delegated from the `nu01.com`
zone by an NS record (TTL 3600), like `rbacr` and `uplink`. Both stages'
records live in it: `tabscan.nu01.com`, `rc.tabscan.nu01.com`, and their
ACM validation names.

## One-time setup

0. Create the zone and its delegation (done 2026-10-10):

   ```bash
   aws route53 create-hosted-zone --name tabscan.nu01.com --caller-reference "tabscan-$(date -u +%s)"
   # then, in the nu01.com zone, an NS record for tabscan.nu01.com with
   # the new zone's four name servers
   ```

1. Deploy the GitHub roles. They're IAM resources, so an administrator
   deploys them, once. The account already has GitHub's OIDC provider
   (from `presence-github-deploy`); in an account without it, add
   `CreateOidcProvider=true`:

   ```bash
   aws cloudformation deploy --region us-east-1 \
     --stack-name tabscan-github-deploy \
     --template-file tabscan_infra/github-deploy.yaml \
     --capabilities CAPABILITY_NAMED_IAM \
     --parameter-overrides "HostedZoneId=$HOSTED_ZONE_ID"   # from the private .env
   ```

   The production role trusts only tokens for `*GA` tags of
   `prodbytes/tabscan`. Its permissions cover the TabScan stacks:
   CloudFormation, S3, CloudFront, ACM, records under `tabscan.nu01.com`
   in the zone, and the site's health check (Route 53 health checks,
   `tabscan-*` alarms and SNS topics, the `LanguageExtensions` transform).
   Run the same command again whenever `github-deploy.yaml` changes.

2. Set the repository variables:

   ```bash
   gh variable set AWS_DEPLOY_ROLE_ARN --body "<DeployRoleArn>"
   gh variable set AWS_DEPLOY_RC_ROLE_ARN --body "<RcDeployRoleArn>"
   gh variable set HOSTED_ZONE_ID --body Z10277161AEN9OU2H73PJ
   # A secret, not a variable: the repository is public, and run logs
   # show variables.
   gh secret set TABSCAN_HEALTH_EMAILS --body "<who gets health alarms>"
   ```
