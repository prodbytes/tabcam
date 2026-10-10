# tabscan_infra

The production (and release-candidate) infrastructure, as CloudFormation
templates.

| Template | Stack | Holds |
|---|---|---|
| [site.yaml](site.yaml) | `tabscan-web` | https://tabscan.nu01.com: the ACM certificate (DNS-validated in the `tabscan.nu01.com` zone), a private S3 bucket, a CloudFront distribution, the Route 53 A/AAAA aliases, and a Route 53 health check of `/app/version.json` that emails `TABSCAN_HEALTH_EMAILS` when it fails |
| [user-data.yaml](user-data.yaml) | `tabscan-user-data` | The bucket of signed-in users' events, `nu01-user-events-<account>` (private, SSE-S3, TLS only, versioned: old versions kept 30 days; CORS for the web app's origins). Not `tabscan-*`, so the deploy roles can't reach it. Shared by production and the RC |
| [identity.yaml](identity.yaml) | `tabscan-identity` | The Cognito identity pool `tabscan` (Google sign-in only, no guests, enhanced flow) and its authenticated role: get, put and delete in `<bucket>/<identity ID>/*`, and list that prefix. Shared by production and the RC |
| [share-api.yaml](share-api.yaml) | `tabscan-share-api` | Sharing captures by email: the `tabscan-share-api` HTTP API (Google JWT authorizer, throttled), its Python function ([tabscan_api/shares/](../tabscan_api/shares)), the grants table (PITR on) and the `tabscan-share-access` role, which the function assumes with a session policy narrowed to one capture's folder (and to reading, for read-only grants) |
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

3. Sign-in and cloud sync (once; again when the templates change). An
   administrator deploys both stacks, since `identity.yaml` makes an IAM
   role; the deploy roles only read their outputs from repository
   variables.

   1. In the Google Cloud project, create the OAuth clients (APIs &
      Services > Credentials):
      - **Web application**: authorized JavaScript origins
        `https://tabscan.nu01.com`, `https://rc.tabscan.nu01.com` and
        `http://localhost:2012`. Its ID is `GOOGLE_WEB_CLIENT_ID`.
      - **Android**: package `com.nu01.tabscan` and the SHA-1 of the key
        that signs the APK (`keytool -list -v -keystore
        ~/.android/debug.keystore -alias androiddebugkey -storepass
        android` for local builds, which are signed with the debug key).
      - **iOS**: bundle ID `com.nu01.tabscan`. Its ID is
        `GOOGLE_IOS_CLIENT_ID`.
   2. Deploy the stacks (`identity.yaml` exports the pool's ID for the
      share API):

      ```bash
      aws cloudformation deploy --region us-east-1 \
        --stack-name tabscan-user-data \
        --template-file tabscan_infra/user-data.yaml
      aws cloudformation deploy --region us-east-1 \
        --stack-name tabscan-identity \
        --template-file tabscan_infra/identity.yaml \
        --capabilities CAPABILITY_IAM \
        --parameter-overrides "GoogleWebClientId=$GOOGLE_WEB_CLIENT_ID"
      ```

   3. Put the IDs in the private `.env` (`GOOGLE_WEB_CLIENT_ID`,
      `GOOGLE_IOS_CLIENT_ID`, `COGNITO_IDENTITY_POOL_ID` from
      `tabscan-identity`'s `IdentityPoolId`, `USER_DATA_BUCKET` from
      `tabscan-user-data`'s `UserDataBucketName`) and in the repository
      variables, for the deploys and releases:

      ```bash
      gh variable set GOOGLE_WEB_CLIENT_ID --body "<web client ID>"
      gh variable set GOOGLE_IOS_CLIENT_ID --body "<iOS client ID>"
      gh variable set COGNITO_IDENTITY_POOL_ID --body "<IdentityPoolId>"
      gh variable set USER_DATA_BUCKET --body "<UserDataBucketName>"
      ```

   They're public identifiers (compiled into the app), not secrets. While
   they're empty, builds have no sign-in and events stay on the device.

4. Sharing captures by email (after step 3; again when
   `share-api.yaml` or `tabscan_api/shares/index.py` changes). An
   administrator runs, with `GOOGLE_WEB_CLIENT_ID` in `.env`:

   ```bash
   bash scripts/deploy-share-api.sh
   ```

   It runs the function's tests, deploys the stack, uploads the code and
   checks the API refuses requests without a token. Put the URL it prints
   in `.env` and the repository variables as `SHARE_API_URL`:

   ```bash
   gh variable set SHARE_API_URL --body "<ApiUrl>"
   ```
