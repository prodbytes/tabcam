# tabscan_infra

The production (and release-candidate) infrastructure, as CloudFormation
templates.

| Template | Stack | Holds |
|---|---|---|
| [site.yaml](site.yaml) | `tabscan-web` | https://tabscan.nu01.com: the ACM certificate (DNS-validated in the `tabscan.nu01.com` zone), a private S3 bucket, a CloudFront distribution, and the Route 53 A/AAAA aliases (uptime: the `nu01-monitor` stack, in the nu01 repository, polls `/app/version.json`) |
| [user-data.yaml](user-data.yaml) | `tabscan-user-data` | The bucket of signed-in users' events, `nu01-user-events-<account>` (private, SSE-S3, TLS only, object events to EventBridge, versioned: old versions kept 30 days; CORS for the web app's origins). Not `tabscan-*`, so the deploy roles can't reach it. Shared by production and the RC |
| [identity.yaml](identity.yaml) | `tabscan-identity` | The Cognito identity pool `tabscan` (Google sign-in through the `accounts.google.com` OpenID Connect provider it makes, for the web, iOS and local web clients, and with `AppleClientId` Sign in with Apple, for the bundle ID; no guests, enhanced flow) and its authenticated role: get, put and delete in `<bucket>/<identity ID>/*`, and list that prefix. Shared by production and the RC |
| [identity.yaml](identity.yaml) | `tabscan-identity-local` | The same for local web builds: the pool `tabscan-local`, trusting the "local - web" client through the same provider, and its own authenticated role on the same bucket |
| [share-api.yaml](share-api.yaml) | `tabscan-share-api` | Sharing captures by email: the `tabscan-share-api` HTTP API (Google JWT authorizer, and with `AppleClientId` an Apple one for the same routes under `/apple`; throttled), its Python function ([tabscan_api/shares/](../tabscan_api/shares)), the grants table (PITR on) and the `tabscan-share-access` role, which the function assumes with a session policy narrowed to one capture's folder (and to reading, for read-only grants) |
| [ocr-repo.yaml](ocr-repo.yaml) | `tabscan-ocr-repo` | The ECR repository `tabscan-ocr` of the cloud OCR image ([tabscan_locr/](../tabscan_locr/README.md)) |
| [ocr.yaml](ocr.yaml) | `tabscan-ocr` | TabScan Premium's cloud OCR: the `tabscan-accounts` table, the `tabscan-ocr` and `tabscan-ocr-api` functions, the API's function URL (the app's `TABSCANNER_OCR_URL`) and the EventBridge rule for page uploads. Deployed by `tabscan_locr/scripts/deploy.sh` |
| [github-deploy.yaml](github-deploy.yaml) | `tabscan-github-deploy` | The `tabscan-github-deploy` role (Deploy workflow, `*GA` tags) and the `tabscan-github-deploy-rc` role (Deploy RC workflow: `*RC*` tags and manual runs from `main`, limited to `tabscan-rc-*` resources and the `rc.tabscan.nu01.com` records), trusting GitHub's OIDC provider |

`scripts/deploy.sh` deploys `tabscan-web`. With `STAGE=rc` it deploys the
release candidate's own copy, `tabscan-rc-web`, for
https://rc.tabscan.nu01.com; `*RC*` tags do that through
[deploy-rc.yml](../.github/workflows/deploy-rc.yml).

Every stack is deployed with the cost-allocation tags `project=tabscan`
and `tenancy` (CloudFormation copies them to the resources that take
tags): `GA` for `tabscan-web`, `RC` for `tabscan-rc-web`, `dev` for
`tabscan-identity-local`, and `shared` for the stacks both stages use
(`tabscan-user-data`, `tabscan-identity`, `tabscan-share-api`,
`tabscan-ocr-repo`, `tabscan-ocr`, `tabscan-github-deploy`).

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
`Z10277161AEN9OU2H73PJ` (`TABSCANNER_HOSTED_ZONE_ID`), delegated from the `nu01.com`
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
     --tags project=tabscan tenancy=shared \
     --parameter-overrides "HostedZoneId=$TABSCANNER_HOSTED_ZONE_ID"   # from the private .env
   ```

   The production role trusts only tokens for `*GA` tags of
   `prodbytes/tabscan`. Its permissions cover the TabScan stacks:
   CloudFormation, S3, CloudFront, ACM, records under `tabscan.nu01.com`
   in the zone, and, until the next GA deploy has deleted them, the site's
   old health check (Route 53 health checks, `tabscan-*` alarms and SNS
   topics, the `LanguageExtensions` transform); remove those statements
   then.
   Run the same command again whenever `github-deploy.yaml` changes.

2. Set the repository variables:

   ```bash
   gh variable set TABSCANNER_AWS_DEPLOY_ROLE_ARN --body "<DeployRoleArn>"
   gh variable set TABSCANNER_AWS_DEPLOY_RC_ROLE_ARN --body "<RcDeployRoleArn>"
   gh variable set TABSCANNER_HOSTED_ZONE_ID --body Z10277161AEN9OU2H73PJ
   ```

3. Sign-in and cloud sync (once; again when the templates change). An
   administrator deploys both stacks, since `identity.yaml` makes an IAM
   role; the deploy roles only read their outputs from repository
   variables.

   1. In the Google Cloud project, create the OAuth clients (APIs &
      Services > Credentials):
      - **Web application**: authorized JavaScript origins
        `https://tabscan.nu01.com`, `https://rc.tabscan.nu01.com` and
        `http://localhost:2012`. Its ID is `TABSCANNER_GOOGLE_WEB_CLIENT_ID`.
      - **Web application** "local - web", for local web builds: JavaScript
        origin `https://local.tabscan.nu01.com:2443`, no redirect URI. Its
        ID is `TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID` (only in the private
        `.env`).
      - **Android**: package `com.nu01.tabscan` and the SHA-1 of the key
        that signs the APK (`keytool -list -v -keystore
        ~/.android/debug.keystore -alias androiddebugkey -storepass
        android` for local builds, which are signed with the debug key).
      - **iOS**: bundle ID `com.nu01.tabscan`. Its ID is
        `TABSCANNER_GOOGLE_IOS_CLIENT_ID`.
   2. Deploy the stacks (`identity.yaml` exports the pool's ID for the
      share API):

      ```bash
      origins=https://tabscan.nu01.com,https://rc.tabscan.nu01.com,http://localhost:2012,https://local.tabscan.nu01.com:2443
      aws cloudformation deploy --region us-east-1 \
        --stack-name tabscan-user-data \
        --template-file tabscan_infra/user-data.yaml \
        --tags project=tabscan tenancy=shared \
        --parameter-overrides "AllowedOrigins=$origins"
      aws cloudformation deploy --region us-east-1 \
        --stack-name tabscan-identity \
        --template-file tabscan_infra/identity.yaml \
        --capabilities CAPABILITY_IAM \
        --tags project=tabscan tenancy=shared \
        --parameter-overrides "GoogleWebClientId=$TABSCANNER_GOOGLE_WEB_CLIENT_ID" \
          "GoogleAppClientIds=$TABSCANNER_GOOGLE_IOS_CLIENT_ID,$TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID" \
          GoogleProviderArn= PoolName=tabscan \
          DeveloperProviderName=login.tabscan.profiles
      # Local web builds' pool, on the same Google provider; its
      # IdentityPoolId is TABSCANNER_COGNITO_LOCAL_IDENTITY_POOL_ID (private
      # .env only).
      provider="$(aws cloudformation describe-stacks --region us-east-1 \
        --stack-name tabscan-identity \
        --query "Stacks[0].Outputs[?OutputKey=='GoogleProviderArn'].OutputValue" --output text)"
      aws cloudformation deploy --region us-east-1 \
        --stack-name tabscan-identity-local \
        --template-file tabscan_infra/identity.yaml \
        --capabilities CAPABILITY_IAM \
        --tags project=tabscan tenancy=dev \
        --parameter-overrides "GoogleWebClientId=$TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID" \
          GoogleAppClientIds= "GoogleProviderArn=$provider" PoolName=tabscan-local \
          DeveloperProviderName=
      ```

      Google sign-in goes through an IAM OpenID Connect provider for
      `accounts.google.com` that `tabscan-identity` makes, not the pools'
      built-in Google login: an app's ID token names its own client as
      well as the web client (on iOS `aud` is the web client, `azp` the
      iOS client), and the built-in login, which takes one client ID,
      refuses it. The provider takes every client in its list:
      `GoogleWebClientId` and `GoogleAppClientIds` (iOS, "local - web", and
      **each Android signing key's client, to add** as they're made). An
      account has one provider per URL, so the local stack uses the main
      stack's (`GoogleProviderArn`).

      The main pool's developer provider, `login.tabscan.profiles`, is how
      [profiles](../specs/profiles.md) get their folder: the share API
      vouches for a profile's ID (`GetOpenIdTokenForDeveloperIdentity`).
      A pool's developer provider can be set once and never changed. Moving to it gave existing users new
      identity IDs (their folders start empty; nothing was stored yet).

      Pass every parameter each time: `deploy` keeps a stack's previous
      value for a parameter left out, not the template's new default.
      `tabscan_locr/scripts/deploy.sh` and `scripts/deploy-share-api.sh`
      pass the local client and the origins to their stacks the same way.

   3. Put the IDs in the private `.env` (`TABSCANNER_GOOGLE_WEB_CLIENT_ID`,
      `TABSCANNER_GOOGLE_IOS_CLIENT_ID`, `TABSCANNER_COGNITO_IDENTITY_POOL_ID` from
      `tabscan-identity`'s `IdentityPoolId`, `TABSCANNER_USER_DATA_BUCKET` from
      `tabscan-user-data`'s `UserDataBucketName`) and in the repository
      variables, for the deploys and releases:

      ```bash
      gh variable set TABSCANNER_GOOGLE_WEB_CLIENT_ID --body "<web client ID>"
      gh variable set TABSCANNER_GOOGLE_IOS_CLIENT_ID --body "<iOS client ID>"
      gh variable set TABSCANNER_COGNITO_IDENTITY_POOL_ID --body "<IdentityPoolId>"
      gh variable set TABSCANNER_USER_DATA_BUCKET --body "<UserDataBucketName>"
      ```

   They're public identifiers (compiled into the app), not secrets. While
   they're empty, builds have no sign-in and events stay on the device.

4. Sharing captures by email (after step 3; again when
   `share-api.yaml` or `tabscan_api/shares/index.py` changes). An
   administrator runs, with `TABSCANNER_GOOGLE_WEB_CLIENT_ID` in `.env`:

   ```bash
   bash scripts/deploy-share-api.sh
   ```

   It runs the function's tests, deploys the stack, uploads the code and
   checks the API refuses requests without a token. When `tabscan-ocr` is
   deployed, it passes its accounts table, so `DELETE /account` deletes a
   user's record there too: run it again after deploying the OCR service. Put the URL it prints
   in `.env` and the repository variables as `TABSCANNER_SHARE_API_URL`:

   ```bash
   gh variable set TABSCANNER_SHARE_API_URL --body "<ApiUrl>"
   ```

5. Sign in with Apple on iOS (optional; App Store guideline 4.8). Off
   until all of this is done:

   1. Join the paid Apple Developer Program (a free Personal Team can't
      sign the capability), and in Certificates, Identifiers & Profiles
      enable **Sign in with Apple** on the App ID `com.nu01.tabscan`
      ("Enable as a primary App ID"). No key, Services ID or domain is
      needed: native sign-in on iOS only.
   2. Redeploy the stacks with Apple trusted, its tokens' audience being
      the bundle ID:

      ```bash
      aws cloudformation deploy --region us-east-1 \
        --stack-name tabscan-identity \
        --template-file tabscan_infra/identity.yaml \
        --capabilities CAPABILITY_IAM \
        --tags project=tabscan tenancy=shared \
        --parameter-overrides "GoogleWebClientId=$TABSCANNER_GOOGLE_WEB_CLIENT_ID" \
          PoolName=tabscan AppleClientId=com.nu01.tabscan
      ```

      Then, with `TABSCANNER_APPLE_SIGN_IN=1` in `.env`,
      `bash scripts/deploy-share-api.sh` (it adds the `/apple` routes and
      their authorizer, and checks `/apple/shared` answers 401 without a
      token) and `bash tabscan_locr/scripts/deploy.sh` (the OCR function
      takes Apple's tokens; without it, Apple users get "Premium needs
      Google sign-in"). Leave the local pool (`tabscan-identity-local`)
      as it is: local builds are web builds, with no Apple sign-in.
   3. Set `TABSCANNER_APPLE_SIGN_IN=1` and the paid team's
      `TABSCANNER_IOS_DEVELOPMENT_TEAM` in `.env`: iOS builds then show
      Sign in with Apple and carry the entitlement
      ([platforms](../specs/platforms.md)).
