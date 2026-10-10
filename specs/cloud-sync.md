# Sign-in and cloud sync

Signing in is needed only to read tabs and to share; anyone can capture.
Signed in, a user's events **sync with S3**, both
ways, so every device they sign in on has the same events, and a new
device, or the web app after a reload, gets them back. Signed out,
nothing leaves the device. It works as Presence's first cloud sync did:
Google sign-in, a Cognito identity pool that turns the Google ID token
into temporary AWS credentials for the user's own folder, and signed S3
requests made by the app itself ([lib/cloud/](../tabscan_app/lib/cloud)).
Sync needs no TabScan server (only [sharing](shared-captures.md) has an
API).

A build has sign-in only when it has all of `TABSCANNER_GOOGLE_WEB_CLIENT_ID`,
`TABSCANNER_COGNITO_IDENTITY_POOL_ID` and `TABSCANNER_USER_DATA_BUCKET` (below). Without them
it's as before: no account button, events only on the device.

## Signed out

Signed out (anonymous), the user can **capture**: scan, and add pages, photos, videos, files and links to their events, and
rename, filter, rotate, clone and delete them. All of it is stored on the
device only. **Read tab** (the processing) and **sharing** need signing
in. **Share with people** only shows signed in. **Share** (as a link, a PDF, text
or files, from a card, the event screen or the text tab editor) and
**Read tab**, tapped signed out, open a
sheet, "Sign in to read tabs" or "Sign in to share", saying why, that
capturing still works and stays on the device, and the sign-in button.
Signing in there closes it and goes on with what was tapped; closing it
does nothing. What was captured signed out goes up at the first sign-in,
as the user's own.

In a build without sign-in set up, nothing asks to sign in: Read tab and
sharing work as before (there'd be no way to sign in).

## Signing in

The [Profile](navigation.md#profile) tab shows the account:

- **Signed out**: "Sign in", what it's for (reading tabs, sharing, and
  backing up to every device; signed out, capturing stays on this
  device), and **Sign in with Google** (on the web, Google's own button),
  with the last sign-in error under it.
- **Signed in**: the account's photo, name and email; the sync status
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
(`us-east-1:<uuid>`), the same on every device for a Google account, in
the user-data bucket:

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
  <ID token>}`. Neither call is signed: the token is the proof. They're
  reused until five minutes before they expire; a refreshed token keeps
  the identity ID and gets new credentials. Signing out, or another
  account signing in, forgets them.
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
  `us-east-1`), `TABSCANNER_COGNITO_IDENTITY_POOL_ID`, `TABSCANNER_USER_DATA_BUCKET`, and for
  [sharing](shared-captures.md) `TABSCANNER_SHARE_API_URL`. All are public
  identifiers, not secrets.

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
  `tabscan`, trusting Google (`accounts.google.com` = the web client ID);
  no guests, no classic flow. The same template, as stack
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
- Both templates pass `aws cloudformation validate-template`; the web and
  Android builds compile with sync set up.
- Not yet verified: a real sign-in and sync, which needs the Google OAuth
  clients and the deployed stacks.

## Known limitations

- **Android release builds from CI** are signed with a fresh debug key
  each run (the app has no release signing key yet), so their SHA-1
  doesn't match the Android OAuth client and Google sign-in fails there.
  Local builds (`scripts/android-install.sh`) use the developer's debug
  key, which the client can list.
- **Web** keeps events in memory, so each visit downloads all of a user's
  events again, videos included.
- An ID token that can't be refreshed quietly (Google wants the user to
  choose an account again) stops sync after an hour, with "Sign in again
  to sync".
- Two devices changing the same event between passes: the later change
  wins whole; the other is lost (S3 keeps it as an old version for 30
  days).
- Tombstones stay forever, on the device and in the folder.
