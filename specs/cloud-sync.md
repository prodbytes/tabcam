# Sign-in and cloud sync

Signing in is needed only to read tabs and to share; anyone can capture.
Signed in, a user's events **sync with S3**, both
ways, so every device they sign in on has the same events, and a new
device, or the web app after a reload, gets them back. Signed out,
nothing leaves the device. It works as Presence's first cloud sync did:
Google sign-in (and, on iOS, Sign in with Apple), a Cognito identity pool
that turns the ID token into temporary AWS credentials for the user's own folder, and signed S3
requests made by the app itself ([lib/cloud/](../tabscan_app/lib/cloud)).
Sync needs no TabScan server (only [sharing](shared-captures.md) has an
API).

A build has sign-in only when it has all of `TABSCANNER_GOOGLE_WEB_CLIENT_ID`,
`TABSCANNER_COGNITO_IDENTITY_POOL_ID` and `TABSCANNER_USER_DATA_BUCKET` (below). Without them
it's as before: no account button, events only on the device. **Sign in
with Apple** is offered on iOS only, in builds with
`TABSCANNER_APPLE_SIGN_IN=1` (below); elsewhere Google is the only sign-in.

## Signed out

Signed out (anonymous), the user can **capture**: scan, and add pages, photos, videos, files and links to their events, and
rename, filter, rotate, clone and delete them. All of it is stored on the
device only. **Reading tabs** (the processing) and **sharing** need
signing in. **Share with people** only shows signed in. Captures made
signed out are read once the user signs in
([tab recognition](tab-recognition.md#reading-by-itself)); the Text view
says so, with **Sign in**. **Share** (as a link, a PDF, text or files,
from a card, the event screen or the Text view) and the Text view's
**Sign in**, tapped signed out, open a sheet, "Sign in to read tabs" or "Sign in to share", saying why, that
capturing still works and stays on the device, and the sign-in buttons
(as on the Profile tab).
Signing in there closes it and goes on with what was tapped; closing it
does nothing. What was captured signed out goes up at the first sign-in,
as the user's own.

In a build without sign-in set up, nothing asks to sign in: reading and
sharing work as before (there'd be no way to sign in).

## Signing in

The [Profile](navigation.md#profile) tab shows the account:

- **Signed out**: "Sign in", what it's for (reading tabs, sharing, and
  backing up to every device; signed out, capturing stays on this
  device), and **Sign in with Google** (on the web, Google's own button),
  with the last sign-in error under it. On iOS with Sign in with Apple set
  up, **Sign in with Apple** comes first, above Google's: Apple's button
  (`SignInWithAppleButton`), black on the light theme and white on the
  dark one, as Apple's Human Interface Guidelines ask, the same size as
  Google's (both 44 points high, at most 320 wide).
- **Signed in**: the account's photo, name and email (signed in with
  Apple, "Signed in with Apple" under the email too; a private relay
  address with no name shows as "Apple ID (private email)", the address
  under it); where Premium is
  set up, the user's role ([cloud OCR](cloud-ocr.md#in-the-app)); the sync status
  ("Syncing…", "Synced at 14:05 (2 uploaded, 1 downloaded)", or why it
  failed, such as "Sign in again to sync"); **Sync now**; **Sign out**,
  which keeps the events on the device; and, where it's set up, the
  [TabScan Premium](cloud-ocr.md#in-the-app) card.

Google sign-in (`google_sign_in`,
[lib/auth/](../tabscan_app/lib/auth)) per platform:

- **Web**: Google Identity Services with FedCM: a quiet auto-select prompt
  at launch, and Google's rendered button. GIS keeps no session, so the
  app keeps the user and ID token in `localStorage`
  (`tabscan.session`) and restores it at launch while the token has more
  than a minute left. Sign out forgets it.
- **Android**: Credential Manager: a quiet check at launch of the
  accounts that signed in before, and Google's sheet for the button.
- **iOS**: the Google Sign-In SDK, which restores the last sign-in. It
  returns to the app through the reversed iOS client ID, a URL scheme in
  `Info.plist` filled from `Private.xcconfig` ([platforms](platforms.md)).

### Sign in with Apple (iOS)

The App Store asks apps that offer Google sign-in to offer an equally
private one too (guideline 4.8), so iOS has **Sign in with Apple**
(`sign_in_with_apple`, pinned, AuthenticationServices;
[apple_auth_service.dart](../tabscan_app/lib/auth/apple_auth_service.dart)),
beside Google, through `MultiAuthService`: one session at a time, with
either provider; signing in with one signs the other out. The session
keeps who, the provider and the ID token.

- **The sheet** asks for the name and email. Each sign-in sends Apple the
  SHA-256 of a fresh random nonce (32 bytes from a secure random), and the
  ID token must carry it back, with Apple's issuer and the same user, or
  the sign-in is refused ("Apple's sign-in reply doesn't match the
  request"). Canceling is no error.
- **Name and email**: Apple sends them only on the first sign-in to the
  app, so they're kept by Apple's user ID for later sign-ins (and kept
  after signing out); the email is in every ID token too. The user may
  hide their email: then it's Apple's private relay address
  (`…@privaterelay.appleid.com`, the token's `is_private_email`), shown as
  above. That address is what sharing and Premium go by: people share
  with it, and it has no Premium ([cloud OCR](cloud-ocr.md#who-is-premium)).
- **The session**: Apple keeps none, and can't renew the ID token without
  a server of TabScan's own, so the app keeps the user and token in a file
  in its private Application Support folder (`apple_sign_in.json`) and
  restores it at launch while the token has more than a minute left. When
  the token expires the user is signed out, "Your Apple sign-in expired:
  sign in again." At launch, a user who stopped using Apple ID with
  TabScan (Settings → Apple ID → Sign in with Apple) is signed out. Sign
  out forgets the session (Apple has no sign-out of its own).
- **Its ID token** is issued for the bundle ID, `com.nu01.tabscan`, which
  the identity pool and the share API trust when set up (below). Each
  provider is its own Cognito identity: the same person signed in with
  Google and with Apple has two folders, and sees only that sign-in's
  events (no account linking).
- **The build**: `TABSCANNER_APPLE_SIGN_IN=1` (`.env`, a dart-define) shows
  the button, and `scripts/dart-defines.sh` then writes
  `CODE_SIGN_ENTITLEMENTS=Runner/Runner.entitlements` (the
  `com.apple.developer.applesignin` entitlement) to the git-ignored
  `Private.xcconfig`. Only a paid Apple Developer Program team can sign
  that entitlement, so without the flag (free Personal Team builds, CI's
  unsigned builds) there are no entitlements and no Apple button
  ([platforms](platforms.md)).
- Not on Android or the web, where Google is the only sign-in.

### Google's token

Every platform's ID token is issued for the **web client** (the server
client ID on Android and iOS), which the identity pool trusts. Local web
builds sign in with the **local web client** instead
(`TABSCANNER_GOOGLE_LOCAL_WEB_CLIENT_ID`, the one with the local origins),
and get their credentials from the **local pool**, `tabscan-local`, which
trusts only that client (a pool can't trust two Google clients). The same
Google account has another identity ID there, so local builds sync to
another folder ([dev environment](dev-environment.md)).
Tokens last an hour; five minutes before one expires the app asks Google
quietly for a new one.

## What's synced, and where

Everything is under the user's **Cognito identity ID**
(`us-east-1:<uuid>`), the same on every device for an account (a Google
account, or an Apple ID: each its own identity), in the user-data bucket:

| Object | Content |
|---|---|
| `<identity>/events/<event id>/event.json` | the event's details, as on the device, with the folder's identity as `owner` and the people it's shared with (`shares`), whether the owner
[hid the images](hidden-images.md) (`hideImages`), but without how it's shared with the user (`sharedBy`, `readOnly`); or its tombstone once deleted. Coming down, the folder it's in, not `owner`, says whose it is |
| `<identity>/events/<event id>/<page id>.<extension>` | each page's file, as stored on the device, with its MIME type (`image/jpeg` for scanned pages, the video's type for videos) |

Links are in `event.json` only: they have no file.
Beside `events/`, the user's folder has `ocr/`: the transcriptions the
[cloud OCR](cloud-ocr.md) service writes for premium users
(`<identity>/ocr/<event id>/<page id>.json`). Sync doesn't touch them;
`CloudOcr` reads them.

Page files never change once written: a rotated page is a new page (see
[library](library.md#events)), so an event's pages are known by their names.
Uploads use S3 Intelligent-Tiering.

## When, and how

A **pass** runs at sign-in, 2 seconds after the user changes an event (a
burst of changes is one pass), every minute while signed in (to bring
other devices' changes), and on **Sync now**. One pass runs at a time; a
request during one runs another right after. Passes wait for the library
to load.

A pass lists the user's folder (with nothing new anywhere, that one
request is the whole pass) and compares it with what last synced, kept
per event in `cloudsync.json` beside the events (by `<folder's
identity>/<event id>`: the `event.json` ETag last sent or taken, and the
event's `updated` then; for one signed-in identity: another starts
over). For each event on the device that's this user's (or no
one's yet):

- **Changed only here** (its `updated` differs from the last sync, or it
  never synced), or missing from the folder: it **goes up**: the pages the
  folder lacks (streamed from the file, so videos aren't held in memory),
  then `scan.json`, then the files of pages it no longer has are deleted.
  It then belongs to this user (`owner`).
- **Changed only in the folder** (its `scan.json` ETag differs): it
  **comes down**: the pages the device lacks (streamed to a file, renamed
  into place when complete), then the event, so it never shows without
  them; local pages it no longer has are deleted.
- **Changed in both**: the later `updated` wins. An event the user changes
  while it's coming down keeps that change, which goes up next.

Events only in the folder come down too; another device's tombstone of an
event never here is just remembered. **Deleting** an event that has synced
leaves a tombstone, which goes up (its page files are deleted from the
folder) and deletes it on the other devices. An event that never synced is
simply deleted.

**Another account's events**: events that synced with one account stay on
the device when another signs in, shown but never uploaded to the new
account. Events made signed out go up to whoever signs in next.

**Shared captures**: after the user's own folder, each pass syncs the
captures shared with them, each in its owner's folder, the same way (but
never uploading a read-only one); see
[shared captures](shared-captures.md#how-it-works).

## Credentials and errors

- **Credentials** (`CognitoCredentials`): the enhanced flow, `GetId` then
  `GetCredentialsForIdentity`, with `Logins: {"accounts.google.com":
  <ID token>}`, or `{"appleid.apple.com": <ID token>}` for Apple's (the
  key follows the token's issuer). Neither call is signed: the token is
  the proof. They're reused until five minutes before they expire; a
  refreshed token of the same provider keeps the identity ID and gets new
  credentials, another provider's gets its own identity. Signing out, or
  another account signing in, forgets them.
- **Requests** (`S3Bucket`, `SigV4Signer`, ported from Presence): `GET`,
  `PUT`, `DELETE` and `ListObjectsV2` to
  `https://<bucket>.s3.<region>.amazonaws.com/`, signed with AWS
  Signature Version 4 in pure Dart (tested against AWS's published
  examples). Page uploads stream with `UNSIGNED-PAYLOAD`; `scan.json`
  goes with its signed SHA-256.
- **Errors**: expired credentials are renewed and the pass tried once
  more; so is a request S3 refuses as signed at the wrong time, after
  correcting the clock by S3's time (still off: "This device's clock is
  off by N min: set it to the right time to sync"). Cognito refusing the
  token shows **"Sign in again to sync"**; anything else "Sync failed
  (HTTP …)" or the error. A failed pass is tried again at the next
  trigger.
- **Settings** (`CloudConfig`, `GoogleConfig`; dart-defines from `.env`,
  or repository variables for the deploys and releases):
  `TABSCANNER_GOOGLE_WEB_CLIENT_ID`, `TABSCANNER_GOOGLE_IOS_CLIENT_ID`, `AWS_REGION` (default
  `us-east-1`), `TABSCANNER_COGNITO_IDENTITY_POOL_ID`, `TABSCANNER_USER_DATA_BUCKET`, for
  [sharing](shared-captures.md) `TABSCANNER_SHARE_API_URL`, and
  `TABSCANNER_APPLE_SIGN_IN` (`1`: Sign in with Apple on iOS; `AppleConfig`).
  All are public, not secrets.

## Infrastructure

In [tabscan_infra/](../tabscan_infra), shared by production, the release
candidate and local builds, and deployed once by an administrator (the
identity stack makes an IAM role; the GitHub deploy roles don't manage
either):

- **`user-data.yaml`**, stack `tabscan-user-data`: the bucket
  `nu01-user-events-<account>` (not `tabscan-*`, so the deploy roles,
  which manage `tabscan-*` buckets, can't reach users' events). Private,
  SSE-S3, TLS only, its object events sent to EventBridge (for
  [cloud OCR](cloud-ocr.md)), versioned (old and deleted versions are kept 30 days,
  so a deletion can be undone), incomplete uploads cleared after a day.
  CORS allows `GET`, `PUT`, `HEAD` and `DELETE` from
  `https://tabscan.nu01.com`, `https://rc.tabscan.nu01.com`,
  `http://localhost:2012` and `https://local.tabscan.nu01.com:2443`.
- **`identity.yaml`**, stack `tabscan-identity`: the identity pool
  `tabscan`, trusting Google (`accounts.google.com` = the web client ID)
  and, with `AppleClientId` set, Apple (`appleid.apple.com` = the bundle ID
  `com.nu01.tabscan`); no guests, no classic flow. The same template, as stack
  `tabscan-identity-local`, makes the local pool `tabscan-local`, trusting
  the local web client. Each pool's authenticated role may only get, put and
  delete objects in `<bucket>/${cognito-identity.amazonaws.com:sub}/*`,
  and list that prefix.

Setting it up (the Google OAuth clients, the stacks, the variables):
[tabscan_infra/README.md](../tabscan_infra/README.md).

## Verified

- Unit tests with an in-memory bucket and two simulated devices: an event
  goes up pages first, naming its `owner`; an unchanged pass is one
  listing; another device's events come down with their pages and don't go
  back up; changes reach the other device; the later change wins; removed
  and rotated pages leave the folder; a deletion reaches other devices and
  new ones never get the event; another account's events aren't uploaded;
  expired credentials are renewed; a rejected token asks to sign in
  again; signed out, nothing syncs. The Cognito client's calls and its
  reuse of credentials, and the SigV4 and S3 tests ported from Presence.
- Sign in with Apple's tests, with a fake Apple sheet and made-up tokens:
  the nonce is a SHA-256 and must come back in the token (another
  nonce, or another user's token, is refused); the name Apple sends once
  is kept for the next sign-in; a hidden email is a private relay address,
  labelled by the provider; the session is restored at launch, not once
  expired, and not for a user who stopped using Apple ID with the app;
  canceling is no error; Apple's token goes to Cognito under
  `appleid.apple.com`, with its own identity, and to the share API under
  `/apple`; both providers' buttons, Apple's first and the same width,
  each signing in with its own; one session at a time.
- `flutter build ios --no-codesign --release` builds with and without
  `TABSCANNER_APPLE_SIGN_IN` (with it, the build has
  `CODE_SIGN_ENTITLEMENTS`; without it, none).
- Both templates pass `aws cloudformation validate-template`; the web and
  Android builds compile with sync set up.
- Not yet verified: a real sign-in and sync, which needs the Google OAuth
  clients and the deployed stacks; a real Sign in with Apple, which also
  needs the paid Apple Developer Program, the App ID's capability and the
  stacks deployed with `AppleClientId`
  ([app stores](app-stores.md#status)).

## Known limitations

- **Android sign-in needs the signing key's SHA-1** in an Android OAuth
  client. CI builds without the upload key secrets are signed with a fresh
  debug key each run, so sign-in fails there. The upload key and Play's
  app signing key each need their own client
  ([app stores](app-stores.md#android-signing)); local builds without the
  upload key use the developer's debug key, which a client can list.
- **Web** keeps events in memory, so each visit downloads all of a user's
  events again, videos included.
- An ID token that can't be refreshed quietly (Google wants the user to
  choose an account again) stops sync after an hour, with "Sign in again
  to sync".
- **Sign in with Apple lasts as long as Apple's ID token** (Apple sets its
  lifetime): the app can't renew it without a server exchanging Apple's
  authorization code for a refresh token (which needs a Sign in with Apple
  private key), so the user signs in again when it expires.
- Sign in with Apple and Google are separate identities: no linking, so
  events synced under one don't show under the other.
- Two devices changing the same event between passes: the later change
  wins whole; the other is lost (S3 keeps it as an old version for 30
  days).
- Tombstones stay forever, on the device and in the folder.
