# tabcam_infra

The production (and release-candidate) infrastructure, as CloudFormation
templates.

| Template | Stack | Holds |
|---|---|---|
| [site.yaml](site.yaml) | `tabcam-web` | https://tabcam.nu01.com: the ACM certificate (DNS-validated in the `tabcam.nu01.com` zone), a private S3 bucket, a CloudFront distribution, and the Route 53 A/AAAA aliases (uptime: the `nu01-monitor` stack, in the nu01 repository, polls `/app/version.json`) |
| [user-data.yaml](user-data.yaml) | `tabcam-user-data` | The bucket of signed-in users' events, `nu01-user-events-<account>` (private, SSE-S3, TLS only, object events to EventBridge, versioned: old versions kept 30 days; CORS for the web app's origins). Not `tabcam-*`, so the deploy roles can't reach it. Shared by production and the RC |
| [identity.yaml](identity.yaml) | `tabcam-identity` | The Cognito identity pool `tabcam` (Google sign-in through the `accounts.google.com` OpenID Connect provider it makes, for the web, iOS and local web clients, and with `AppleClientId` Sign in with Apple, for the bundle ID; no guests, enhanced flow) and its authenticated role: get, put and delete in `<bucket>/<identity ID>/*`, and list that prefix. Shared by production and the RC |
| [identity.yaml](identity.yaml) | `tabcam-identity-local` | The same for local web builds: the pool `tabcam-local`, trusting the "local - web" client through the same provider, and its own authenticated role on the same bucket |
| [share-api.yaml](share-api.yaml) | `tabcam-share-api` | Sharing captures by email: the `tabcam-share-api` HTTP API (Google JWT authorizer, and with `AppleClientId` an Apple one for the same routes under `/apple`; throttled), its Python function ([tabcam_api/shares/](../tabcam_api/shares)), the grants table (PITR on) and the `tabcam-share-access` role, which the function assumes with a session policy narrowed to one capture's folder (and to reading, for read-only grants) |
| [ocr-repo.yaml](ocr-repo.yaml) | `tabcam-ocr-repo` | The ECR repository `tabcam-ocr` of the cloud OCR image ([tabcam_locr/](../tabcam_locr/README.md)) |
| [ocr.yaml](ocr.yaml) | `tabcam-ocr` | TabCam Premium's cloud OCR: the `tabcam-accounts` table, the `tabcam-ocr` and `tabcam-ocr-api` functions, the API's function URL (the app's `TABCAM_OCR_URL`) and the EventBridge rule for page uploads. Deployed by `tabcam_locr/scripts/deploy.sh` |
| [github-deploy.yaml](github-deploy.yaml) | `tabcam-github-deploy` | The `tabcam-github-deploy` role (Deploy workflow, `*GA` tags) and the `tabcam-github-deploy-rc` role (Deploy RC workflow: `*RC*` tags and manual runs from `main`, limited to `tabcam-rc-*` resources and the `rc.tabcam.nu01.com` records), trusting GitHub's OIDC provider |

`scripts/deploy.sh` deploys `tabcam-web`. With `STAGE=rc` it deploys the
release candidate's own copy, `tabcam-rc-web`, for
https://rc.tabcam.nu01.com; `*RC*` tags do that through
[deploy-rc.yml](../.github/workflows/deploy-rc.yml).

Every stack is deployed with the cost-allocation tags `project=tabcam`
and `tenancy` (CloudFormation copies them to the resources that take
tags): `GA` for `tabcam-web`, `RC` for `tabcam-rc-web`, `dev` for
`tabcam-identity-local`, and `shared` for the stacks both stages use
(`tabcam-user-data`, `tabcam-identity`, `tabcam-share-api`,
`tabcam-ocr-repo`, `tabcam-ocr`, `tabcam-github-deploy`).

## The distribution

| Path | Origin |
|---|---|
| default (`/`) | S3 `index.html`, the [index page](../tabcam_index) that redirects to `/app/` |
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
4. checks that `https://tabcam.nu01.com/app/version.json` reports the
   tag's version.

`scripts/deploy.sh` also runs by hand with admin credentials (inside
devbox): `TAG=0.1.<Z>-GA bash scripts/deploy.sh`.

## DNS

`tabcam.nu01.com` has its own public Route 53 zone,
`Z01245733BIHST1A417HE` (`TABCAM_HOSTED_ZONE_ID`), delegated from the `nu01.com`
zone by an NS record (TTL 3600), like `rbacr` and `uplink`. Both stages'
records live in it: `tabcam.nu01.com`, `rc.tabcam.nu01.com`, and their
ACM validation names.

## One-time setup

0. Create the zone and its delegation (done 2026-10-10):

   ```bash
   aws route53 create-hosted-zone --name tabcam.nu01.com --caller-reference "tabcam-$(date -u +%s)"
   # then, in the nu01.com zone, an NS record for tabcam.nu01.com with
   # the new zone's four name servers
   ```

1. Deploy the GitHub roles. They're IAM resources, so an administrator
   deploys them, once. The account already has GitHub's OIDC provider
   (from `presence-github-deploy`); in an account without it, add
   `CreateOidcProvider=true`:

   ```bash
   aws cloudformation deploy --region us-east-1 \
     --stack-name tabcam-github-deploy \
     --template-file tabcam_infra/github-deploy.yaml \
     --capabilities CAPABILITY_NAMED_IAM \
     --tags project=tabcam tenancy=shared \
     --parameter-overrides "HostedZoneId=$TABCAM_HOSTED_ZONE_ID"   # from the private .env
   ```

   The production role trusts only tokens for `*GA` tags of
   `prodbytes/tabcam`. Its permissions cover the TabCam stacks:
   CloudFormation, S3, CloudFront, ACM, records under `tabcam.nu01.com`
   in the zone, and, until the next GA deploy has deleted them, the site's
   old health check (Route 53 health checks, `tabcam-*` alarms and SNS
   topics, the `LanguageExtensions` transform); remove those statements
   then.
   Run the same command again whenever `github-deploy.yaml` changes.

2. Set the repository variables:

   ```bash
   gh variable set TABCAM_AWS_DEPLOY_ROLE_ARN --body "<DeployRoleArn>"
   gh variable set TABCAM_AWS_DEPLOY_RC_ROLE_ARN --body "<RcDeployRoleArn>"
   gh variable set TABCAM_HOSTED_ZONE_ID --body Z01245733BIHST1A417HE
   ```

3. Sign-in and cloud sync (once; again when the templates change). An
   administrator deploys both stacks, since `identity.yaml` makes an IAM
   role; the deploy roles only read their outputs from repository
   variables.

   1. In the Google Cloud project, create the OAuth clients (APIs &
      Services > Credentials):
      - **Web application**: authorized JavaScript origins
        `https://tabcam.nu01.com`, `https://rc.tabcam.nu01.com` and
        `http://localhost:2012`. Its ID is `TABCAM_GOOGLE_WEB_CLIENT_ID`.
      - **Web application** "local - web", for local web builds: JavaScript
        origin `https://local.tabcam.nu01.com:2443`, no redirect URI. Its
        ID is `TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID` (only in the private
        `.env`).
      - **Android**: package `com.nu01.tabcam` and the SHA-1 of the key
        that signs the APK (`keytool -list -v -keystore
        ~/.android/debug.keystore -alias androiddebugkey -storepass
        android` for local builds, which are signed with the debug key).
      - **iOS**: bundle ID `com.nu01.tabcam`. Its ID is
        `TABCAM_GOOGLE_IOS_CLIENT_ID`.
   2. Deploy the stacks (`identity.yaml` exports the pool's ID for the
      share API):

      ```bash
      origins=https://tabcam.nu01.com,https://rc.tabcam.nu01.com,http://localhost:2012,https://local.tabcam.nu01.com:2443
      aws cloudformation deploy --region us-east-1 \
        --stack-name tabcam-user-data \
        --template-file tabcam_infra/user-data.yaml \
        --tags project=tabcam tenancy=shared \
        --parameter-overrides "AllowedOrigins=$origins"
      aws cloudformation deploy --region us-east-1 \
        --stack-name tabcam-identity \
        --template-file tabcam_infra/identity.yaml \
        --capabilities CAPABILITY_IAM \
        --tags project=tabcam tenancy=shared \
        --parameter-overrides "GoogleWebClientId=$TABCAM_GOOGLE_WEB_CLIENT_ID" \
          "GoogleAppClientIds=$TABCAM_GOOGLE_IOS_CLIENT_ID,$TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID" \
          GoogleProviderArn= PoolName=tabcam \
          DeveloperProviderName=login.tabcam.profiles
      # Local web builds' pool, on the same Google provider; its
      # IdentityPoolId is TABCAM_COGNITO_LOCAL_IDENTITY_POOL_ID (private
      # .env only).
      provider="$(aws cloudformation describe-stacks --region us-east-1 \
        --stack-name tabcam-identity \
        --query "Stacks[0].Outputs[?OutputKey=='GoogleProviderArn'].OutputValue" --output text)"
      aws cloudformation deploy --region us-east-1 \
        --stack-name tabcam-identity-local \
        --template-file tabcam_infra/identity.yaml \
        --capabilities CAPABILITY_IAM \
        --tags project=tabcam tenancy=dev \
        --parameter-overrides "GoogleWebClientId=$TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID" \
          GoogleAppClientIds= "GoogleProviderArn=$provider" PoolName=tabcam-local \
          DeveloperProviderName=
      ```

      Google sign-in goes through an IAM OpenID Connect provider for
      `accounts.google.com` that `tabcam-identity` makes, not the pools'
      built-in Google login: an app's ID token names its own client as
      well as the web client (on iOS `aud` is the web client, `azp` the
      iOS client), and the built-in login, which takes one client ID,
      refuses it. The provider takes every client in its list:
      `GoogleWebClientId` and `GoogleAppClientIds` (iOS, "local - web", and
      **each Android signing key's client, to add** as they're made). An
      account has one provider per URL, so the local stack uses the main
      stack's (`GoogleProviderArn`).

      The main pool's developer provider, `login.tabcam.profiles`, is how
      [profiles](../specs/profiles.md) get their folder: the share API
      vouches for a profile's ID (`GetOpenIdTokenForDeveloperIdentity`).
      A pool's developer provider can be set once and never changed. Moving to it gave existing users new
      identity IDs (their folders start empty; nothing was stored yet).

      Pass every parameter each time: `deploy` keeps a stack's previous
      value for a parameter left out, not the template's new default.
      `tabcam_locr/scripts/deploy.sh` and `scripts/deploy-share-api.sh`
      pass the local client and the origins to their stacks the same way.

   3. Put the IDs in the private `.env` (`TABCAM_GOOGLE_WEB_CLIENT_ID`,
      `TABCAM_GOOGLE_IOS_CLIENT_ID`, `TABCAM_COGNITO_IDENTITY_POOL_ID` from
      `tabcam-identity`'s `IdentityPoolId`, `TABCAM_USER_DATA_BUCKET` from
      `tabcam-user-data`'s `UserDataBucketName`) and in the repository
      variables, for the deploys and releases:

      ```bash
      gh variable set TABCAM_GOOGLE_WEB_CLIENT_ID --body "<web client ID>"
      gh variable set TABCAM_GOOGLE_IOS_CLIENT_ID --body "<iOS client ID>"
      gh variable set TABCAM_COGNITO_IDENTITY_POOL_ID --body "<IdentityPoolId>"
      gh variable set TABCAM_USER_DATA_BUCKET --body "<UserDataBucketName>"
      ```

   They're public identifiers (compiled into the app), not secrets. While
   they're empty, builds have no sign-in and events stay on the device.

4. Sharing captures by email (after step 3; again when
   `share-api.yaml` or `tabcam_api/shares/index.py` changes). An
   administrator runs, with `TABCAM_GOOGLE_WEB_CLIENT_ID` in `.env`:

   ```bash
   bash scripts/deploy-share-api.sh
   ```

   It runs the function's tests, deploys the stack, uploads the code and
   checks the API refuses requests without a token. When `tabcam-ocr` is
   deployed, it passes its accounts table, so `DELETE /account` deletes a
   user's record there too: run it again after deploying the OCR service. Put the URL it prints
   in `.env` and the repository variables as `TABCAM_SHARE_API_URL`:

   ```bash
   gh variable set TABCAM_SHARE_API_URL --body "<ApiUrl>"
   ```

5. Sign in with Apple on iOS (optional; App Store guideline 4.8). Off
   until all of this is done:

   1. Join the paid Apple Developer Program (a free Personal Team can't
      sign the capability), and in Certificates, Identifiers & Profiles
      enable **Sign in with Apple** on the App ID `com.nu01.tabcam`
      ("Enable as a primary App ID"). No key, Services ID or domain is
      needed: native sign-in on iOS only.
   2. Redeploy the stacks with Apple trusted, its tokens' audience being
      the bundle ID:

      ```bash
      aws cloudformation deploy --region us-east-1 \
        --stack-name tabcam-identity \
        --template-file tabcam_infra/identity.yaml \
        --capabilities CAPABILITY_IAM \
        --tags project=tabcam tenancy=shared \
        --parameter-overrides "GoogleWebClientId=$TABCAM_GOOGLE_WEB_CLIENT_ID" \
          PoolName=tabcam AppleClientId=com.nu01.tabcam
      ```

      Then, with `TABCAM_APPLE_SIGN_IN=1` in `.env`,
      `bash scripts/deploy-share-api.sh` (it adds the `/apple` routes and
      their authorizer, and checks `/apple/shared` answers 401 without a
      token) and `bash tabcam_locr/scripts/deploy.sh` (the OCR function
      takes Apple's tokens; without it, Apple users get "Premium needs
      Google sign-in"). Leave the local pool (`tabcam-identity-local`)
      as it is: local builds are web builds, with no Apple sign-in.
   3. Set `TABCAM_APPLE_SIGN_IN=1` and the paid team's
      `TABCAM_IOS_DEVELOPMENT_TEAM` in `.env`: iOS builds then show
      Sign in with Apple and carry the entitlement
      ([platforms](../specs/platforms.md)).
