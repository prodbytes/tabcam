# Sign-in and cloud sync

Signing in is needed only to read tabs and to share; anyone can capture.
Signed in, a user's events **sync with S3**, both
ways, so every device they sign in on has the same events, and a new
device, or the web app after a reload, gets them back. Signed out,
nothing leaves the device. It works as Presence's first cloud sync did:
Google sign-in (and, on iOS, Sign in with Apple), a Cognito identity pool
that turns the ID token into temporary AWS credentials for the user's own folder, and signed S3
requests made by the app itself ([lib/cloud/](../tabcam_app/lib/cloud)).
Sync needs no TabCam server (only [sharing](shared-captures.md) has an
API).

A build has sign-in only when it has all of `TABCAM_GOOGLE_WEB_CLIENT_ID`,
`TABCAM_COGNITO_IDENTITY_POOL_ID` and `TABCAM_USER_DATA_BUCKET` (below). Without them
it's as before: no account button, events only on the device. **Sign in
with Apple** is offered on iOS only, in builds with
`TABCAM_APPLE_SIGN_IN=1` (below); elsewhere Google is the only sign-in.

## Signed out

Signed out, the app is only the [welcome](navigation.md#signed-out-the-welcome):
nothing can be captured, read or shared until the user signs in. Events
already on the device (from before, or another user's) stay there; the
first sign-in's sync takes those that belong to no one as the user's own.

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
  which keeps the events on the device; where it's set up, the
  [TabCam Premium](cloud-ocr.md#in-the-app) card; and last, in the
  error color, **Delete account**, "Deletes your events in the cloud and
  on this device, and your shares." ([below](#deleting-the-account)).

Google sign-in (`google_sign_in`,
[lib/auth/](../tabcam_app/lib/auth)) per platform:

- **Web**: Google Identity Services with FedCM: a quiet auto-select prompt
  at launch, and Google's rendered button. GIS keeps no session, so the
  app keeps the user and ID token in `localStorage`
  (`tabcam.session`) and restores it at launch while the token has more
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
[apple_auth_service.dart](../tabcam_app/lib/auth/apple_auth_service.dart)),
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
  a server of TabCam's own, so the app keeps the user and token in a file
  in its private Application Support folder (`apple_sign_in.json`) and
  restores it at launch while the token has more than a minute left. When
  the token expires the user is signed out, "Your Apple sign-in expired:
  sign in again." At launch, a user who stopped using Apple ID with
  TabCam (Settings → Apple ID → Sign in with Apple) is signed out. Sign
  out forgets the session (Apple has no sign-out of its own).
- **Its ID token** is issued for the bundle ID, `com.nu01.tabcam`, which
  the identity pool and the share API trust when set up (below). Each
  provider is its own Cognito identity: the same person signed in with
  Google and with Apple has two folders, and sees only that sign-in's
  events (no account linking).
- **The build**: `TABCAM_APPLE_SIGN_IN=1` (`.env`, a dart-define) shows
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
client ID on Android and iOS: its `aud`). An app's token also names the
app's own client (`azp`: the iOS client, or the Android signing key's), so
the pools trust Google through an IAM OpenID Connect provider for
`accounts.google.com` that lists every TabCam client (web, iOS, local
web, and the Android clients as they're made), not the pools' built-in
Google login, which takes one client ID and refused the apps' tokens: on
iOS, sync and the Premium check failed with "Token is not from a supported
provider of this identity pool". The app's `Logins` key is still
`accounts.google.com`. Local web builds sign in with the **local web
client** instead (`TABCAM_GOOGLE_LOCAL_WEB_CLIENT_ID`, the one with
the local origins), and get their credentials from the **local pool**,
`tabcam-local`, on the same provider. The same
Google account has another identity ID there, so local builds sync to
another folder ([dev environment](dev-environment.md)).
Tokens last an hour; five minutes before one expires the app asks Google
quietly for a new one.

## What's synced, and where

Everything is under the user's **Cognito identity ID**
(`us-east-1:<uuid>`), in the user-data bucket: their
[profile](profiles.md)'s, the same on every device and for every account
linked to the profile (a Google account, an Apple ID). Builds without
the share API (local web builds) use the sign-in's own identity instead:

| Object | Content |
|---|---|
| `<identity>/events/<event id>/event.json` | the event's details, as on the device, with the folder's identity as `owner` and the people it's shared with (`shares`), whether the owner
[hid the images](hidden-images.md) (`hideImages`), but without how it's shared with the user (`sharedBy`, `readOnly`); or its tombstone once deleted. Coming down, the folder it's in, not `owner`, says whose it is |
| `<identity>/events/<event id>/<page id>.<extension>` | each page's file, as stored on the device, with its MIME type by extension (`image/jpeg` for scanned pages, `video/mp4`, `audio/mpeg`, `application/pdf`, ...) |

Links are in `event.json` only: they have no file.
Beside `events/`, the user's folder has `ocr/`: the transcriptions the
[cloud OCR](cloud-ocr.md) service writes for premium users
(`<identity>/ocr/<event id>/<page id>.json`). Sync doesn't touch them;
`CloudOcr` reads them.

Each page's name (its `title`, [renamed](event-screen.md) by the user)
is in `event.json` and kept coming back down, for every kind of file.

Page files never change once written: a rotated page is a new page (see
[library](library.md#events)), so an event's pages are known by their names.
Uploads use S3 Intelligent-Tiering.

## When, and how

A **pass** runs at sign-in, 2 seconds after the user changes an event (a
burst of changes is one pass), every 10 seconds while signed in and the
app is in front (to bring other devices' changes; a pass with nothing new
is one listing; every minute while the app is behind, as long as it
runs; again after signing out and back in), at once when the app comes
back to the front (a tab shown again, the phone app reopened), and on
**Sync now**. So a change on one device (a rename, a file added or
moved) shows on the others within seconds. One pass runs at a time; a
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
  **comes down**: the event at once, its pages' files after (see
  [Listed first, files after](#listed-first-files-after)); local pages
  it no longer has are deleted.
- **Changed in both**: the later `updated` wins. An event the user changes
  while it's coming down keeps that change, which goes up next.

Events only in the folder come down too, newest first; another device's
tombstone of an event never here is just remembered.

### Listed first, files after

So a device that has nothing yet (a new phone, and the web at every
visit) shows the user's captures quickly:

- A pass first fetches every `scan.json` that changed, **8 at a time**,
  and shows those captures at once.
- Their pages' files then **download in the background, 4 at a time**:
  pictures and PDFs before videos and recordings, the newest captures
  first. Each is streamed to a file and renamed into place when complete,
  so a broken download leaves nothing.
- Until a file is here, its preview (the capture's card on Home, its
  thumbnail in the file list) shows a **spinner**
  (`Library.isArriving`), and whatever needs the file (opening it, the
  tab's reading, Clone, Rotate, exports) **waits for it**
  (`Library.original` and `path`). Uploads don't wait: a file still
  arriving is already in the folder.
- A file that fails to come stays loading and is **asked for again at the
  next pass**, as is one the app closed before it came; a file whose page
  or capture went is dropped, and what waited for it fails. **Deleting** an event that has synced
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

## Deleting the account

App Store guideline 5.1.1(v) and Google Play want apps that make
accounts to delete them from inside the app. A TabCam account is the
user's Google sign-in, their Cognito identity and folder, their grants in
the [share API](shared-captures.md#how-it-works) and their record in the
[cloud OCR](cloud-ocr.md) service; **Delete account**, on the signed-in
Profile (and the same panel on the web), deletes all of it
([lib/cloud/account_deletion.dart](../tabcam_app/lib/cloud/account_deletion.dart),
[lib/screens/delete_account.dart](../tabcam_app/lib/screens/delete_account.dart)).

**Confirming**: a dialog, "Delete your account?", says what goes (all
their events, in the cloud and on this device; their shares, so the
people they shared captures with lose them; the captures shared with
them, which stop showing), "It can't be undone." (in the error color),
that their Google account isn't deleted, and, where Premium is set up,
that a TabCam Premium subscription isn't cancelled: on the web, "cancel
it on Substack, where you subscribed"; in the Android and iOS apps only
"it's managed where you bought it" (no purchase links in the apps). It
also asks to sign out on their other devices first (below). **Cancel**
or **Delete account** (red).

**Deleting**, in a dialog that can't be dismissed while it runs, with
the step and a progress bar ("Deleting your files in the cloud (1000 of
1500)…", "Deleting your shares…", "Deleting your events on this
device (3 of 7)…", "Signing out…"). Sync is paused first (after the
running pass), so nothing goes up while the folder empties:

1. **The folder**: every object under `<identity>/` (events, page files,
   tombstones, `ocr/` transcriptions) is listed (ListObjectsV2, every
   page) and deleted 1000 at a time with DeleteObjects (`POST /?delete`,
   quiet, so S3 lists only the keys it couldn't delete), with the
   identity's own credentials. It lists again after, up to three rounds,
   for a transcription written meanwhile. On the web, before the bucket's
   CORS allows `POST`, it deletes one key at a time instead. Expired
   credentials or a skewed clock get one more try, as for a pass.
2. **The share API**, `DELETE /account` (when the build has sharing):
   the grants of the user's captures, the grants to their address, their
   record in the OCR service's accounts table, and last their Cognito
   identity ([shared captures](shared-captures.md#how-it-works)).
3. **This device**: the user's events (their identity's, those not
   synced yet, and copies of captures shared with them), tombstones
   included, removed without leaving tombstones; `cloudsync.json` and
   `cloudocr.json` are reset. Events of another account that used the
   device stay.
4. **Signing out**. The dialog closes and a message says "Your TabCam
   account was deleted."

**Failures** stop it where they happen and say what was and wasn't
deleted, with **Try again** and **Close**: keys S3 wouldn't delete ("2
of 300 files in the cloud couldn't be deleted. Nothing else was deleted,
and you are still signed in: try again."), a listing that failed, the
share API refusing ("Your files in the cloud were deleted, but not your
shares: …"), Cognito wanting a new sign-in. The user stays signed in and
sync resumes (the account still exists, so a pass may upload the
device's events again; trying again deletes them again). Each step is
safe to repeat. Only once the cloud parts are done is anything on the
device deleted; if that then fails, the user is signed out all the same
and told to delete what's left from Home.

**Not deleted**, and why:

- **Old versions in the bucket**: it's versioned, and the identity's
  credentials can't delete versions, so deleted objects stay as
  noncurrent versions until the lifecycle rule expires them, **30 days**
  later; nobody can reach them without an administrator.
- **Backups and logs**: the grants table and the accounts table have
  point-in-time recovery (35 days); the share API's and the OCR
  service's logs (30 days) name identity IDs.
- **The Google account**, and Google's record that TabCam was granted
  sign-in (the user removes it in their Google account's settings).
- **rbacr and Substack**: a Premium role or subscription is kept by
  rbacr and Substack, not TabCam; the user cancels it where they
  bought it.
- **Builds without the share API** can't delete the grants nor the
  Cognito identity (only the folder and the device): the identity's role
  can't delete identities, so that's done by the share API's function.
  Production and RC builds have it.

**Other devices** still signed in keep their credentials for up to an
hour; a pass there in that time would upload their events again, under
the deleted identity (where no one can reach them). Hence the dialog's
"sign out there first". After that hour their sync fails ("Sign in again
to sync"), and signing in again makes a new, empty identity, to which the
old account's events on that device aren't uploaded.

**Without the app** (Google Play's "delete account URL"): the web app
has the same panel, so https://tabcam.nu01.com/app/ (sign in, Profile,
Delete account) deletes an account from any browser. Proposed for the
store listing: a static page on the index site,
`https://tabcam.nu01.com/delete-account`, that names TabCam and its
developer, lists those steps, says what's deleted and what's kept for 30
days, and gives a contact address for people who can't sign in any more
(to be done with the privacy policy page, [app stores](app-stores.md);
the deploy uploads only `index.html` today).

## Credentials and errors

- **Credentials** (`ProfileCredentials`, in builds with the share API):
  the share API's `POST /profile/credentials` vouches for the profile
  (a Cognito OpenID token for its developer identity), then
  `GetCredentialsForIdentity` with `Logins:
  {"cognito-identity.amazonaws.com": <that token>}`; reused like the
  others ([profiles](profiles.md#storage)). When the same user's folder
  changes, their own captures on the device move to the new one.
- **Credentials** (`CognitoCredentials`, without the share API): the
  enhanced flow, `GetId` then
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
  `TABCAM_GOOGLE_WEB_CLIENT_ID`, `TABCAM_GOOGLE_IOS_CLIENT_ID`, `AWS_REGION` (default
  `us-east-1`), `TABCAM_COGNITO_IDENTITY_POOL_ID`, `TABCAM_USER_DATA_BUCKET`, for
  [sharing](shared-captures.md) `TABCAM_SHARE_API_URL`, and
  `TABCAM_APPLE_SIGN_IN` (`1`: Sign in with Apple on iOS; `AppleConfig`).
  All are public, not secrets.

## Infrastructure

In [tabcam_infra/](../tabcam_infra), shared by production, the release
candidate and local builds, and deployed once by an administrator (the
identity stack makes an IAM role; the GitHub deploy roles don't manage
either):

- **`user-data.yaml`**, stack `tabcam-user-data`: the bucket
  `nu01-user-events-<account>` (not `tabcam-*`, so the deploy roles,
  which manage `tabcam-*` buckets, can't reach users' events). Private,
  SSE-S3, TLS only, its object events sent to EventBridge (for
  [cloud OCR](cloud-ocr.md)), versioned (old and deleted versions are kept 30 days,
  so a deletion can be undone), incomplete uploads cleared after a day.
  CORS allows `GET`, `PUT`, `HEAD`, `DELETE` and `POST` (DeleteObjects,
  for [deleting the account](#deleting-the-account)) from
  `https://tabcam.nu01.com`, `https://rc.tabcam.nu01.com`,
  `http://localhost:2012` and `https://local.tabcam.nu01.com:2443`.
- **`identity.yaml`**, stack `tabcam-identity`: the identity pool
  `tabcam`, trusting Google through the `accounts.google.com` OpenID
  Connect provider it makes (`GoogleWebClientId` and `GoogleAppClientIds`)
  and, with `AppleClientId` set, Apple (`appleid.apple.com` = the bundle ID
  `com.nu01.tabcam`); no guests, no classic flow. The same template, as stack
  `tabcam-identity-local`, makes the local pool `tabcam-local` on the
  same provider (`GoogleProviderArn`). Each pool's authenticated role may only get, put and
  delete objects in `<bucket>/${cognito-identity.amazonaws.com:sub}/*`,
  and list that prefix.

Setting it up (the Google OAuth clients, the stacks, the variables):
[tabcam_infra/README.md](../tabcam_infra/README.md).

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
  `TABCAM_APPLE_SIGN_IN` (with it, the build has
  `CODE_SIGN_ENTITLEMENTS`; without it, none).
- Account deletion, over the in-memory bucket and share API: the
  folder (pages, tombstones, transcriptions) empties, the shares go both
  ways (the other user's next pass drops the copy), only another
  account's event stays on the device, and it signs out; 1500 objects go
  in two batches, with progress; keys S3 keeps, or the share API
  failing, stop it with the user still signed in and nothing on the
  device deleted, and trying again finishes; expired credentials are
  renewed once. Widget tests: Cancel deletes nothing; confirming shows
  the progress, then the message, signed out; a failure shows why, with
  Try again. The S3 client's DeleteObjects request (signed, with
  `Content-MD5`, escaped keys) and its errors.
- The templates pass `aws cloudformation validate-template`; the web and
  Android builds compile with sync set up.
- Not yet verified: a real sign-in and sync, which needs the Google OAuth
  clients and the deployed stacks; a real account deletion, which also
  needs the updated `tabcam-user-data` (CORS) and `tabcam-share-api`
  stacks; a real Sign in with Apple, which also needs the paid Apple
  Developer Program, the App ID's capability and the stacks deployed with
  `AppleClientId` ([app stores](app-stores.md#status)).

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
