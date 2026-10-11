# TabScan Premium: cloud OCR

Premium users' scans are **transcribed in the cloud as they sync**: the
event's text tab appears by itself, read more accurately than on the
phone, and on the web too. Free users keep [on-device reading](tab-recognition.md)
and, on the web, are offered the upgrade. The service is
[tabscan_locr/](../tabscan_locr/README.md), two AWS Lambda functions.

A build has Premium only with [cloud sync](cloud-sync.md) set up and
`TABSCANNER_OCR_URL` (the service's function URL) set. Without it the app is
as before.

## Who is premium

[rbacr](https://github.com/prodbytes/rbacr) decides: the role `premium`
in its `tabscan` system (`premium` implies `free`), for the user's verified
Google address. People get it by:

- **Subscribing** to prodbytes.substack.com with the same Google address:
  rbacr's Stripe sync grants the `tabscan` system's subscriber role,
  `premium`, for the paid period.
- **A voucher**, redeemed on rbacr's own page (https://rbacr.nu01.com/me,
  signing in with Google).
- A root's grant in rbacr.

The service asks rbacr (`POST /api/check`) with a root-owned API token kept
in AWS Secrets Manager (`tabscan/rbacr-token`), never in the app. If rbacr
can't answer, the user is not premium for now. A "yes" is trusted for at
most 5 minutes (less if the grant ends sooner), a "no" for 1 minute.

## Transcription

1. Cloud sync uploads a page image (`.img`, `.jpg`, `.jpeg`, `.png`,
   `.webp`) to `<identity>/events/<event id>/`. The bucket sends the
   upload to EventBridge, which calls `tabscan-ocr-api`.
2. It looks up the identity's verified address (recorded by `/account`,
   below), asks rbacr, and for premium users invokes `tabscan-ocr`.
   Free users' pages stop there.
3. `tabscan-ocr` reads the page and writes
   `<identity>/ocr/<event id>/<page id>.json`:
   `{page, status, text, staves, lines, seconds, engines, version, created}`,
   `status` being `ok`, `no-tab` or `error`.
4. Deleting a page (or its event) in the bucket deletes its transcription.

**Reading a page**: the page is found and flattened if it's a photo, red
ink dropped, the light evened out and the page scaled to 2800 px. Each tab
string line is a row of dashes: they're found, grouped into staves (six
lines `e B G D A E`, four `G D A E`), and each line is cut out and read
by Tesseract (one line, tab characters only), PaddleOCR and RapidOCR. Each
word goes at the column its position implies, from where the line's dashes
start, so the dashes the engines drop come back. Per line, the reading
closest to the other two (fewest token edits between dashes) wins. Lines
are padded with dashes to their staff's width.

**Notations**: the rest of the page, with the staves blanked out, is read
by RapidOCR at half size (1400 px). Its words (confidence 0.5 or more) are
grouped into lines by height; each word goes at the column of the nearest
staff it lines up with, so chord names stay over their notes. Lines that
are notations, not noise (as on the device:
[notations around the tab](tab-recognition.md#notations-around-the-tab)),
go between the staves where they are on the page; staves are separated by
a blank line, and text sits right above the staff that follows it. A page
with text but no tab is still `no-tab`.

## In the app

`CloudOcr` ([lib/cloud/cloud_ocr.dart](../tabscan_app/lib/cloud/cloud_ocr.dart)):

- **Status**: at sign-in, and each time the Profile tab (or the account
  sheet, from an event's Upgrade on the web) opens, the app
  calls `POST /account` with the user's Google ID token. The service checks
  the token (signed by Google, issued for TabScan's web client or the
  local web client, verified address), asks the main identity pool for its identity ID
  (so local web builds, whose identities are in the local pool, get 401), records identity →
  address, and answers `{email, premium, expiresAt, checked, upgradeUrl,
  voucherUrl}`.
- **Results**: after each sync pass, a premium user's app lists
  `<identity>/ocr/`. Once every image page of one of their synced events
  has a result, the `ok` texts, in page order and separated by a blank
  line, become the event's text tab, which then syncs like any change. It
  writes the text tab only while it's empty or still the text it wrote
  (kept in `cloudocr.json`), and not marked correct, so it never replaces
  the user's edits, an on-device reading or a checked text tab. New pages update it the same way.
- **Pages from before upgrading**: an event whose pages still lack results
  two minutes after its last change is sent to `POST /transcribe
  {eventId}` (once per event per session), which queues its untranscribed
  pages.
- **Reading by itself** ([tab recognition](tab-recognition.md#reading-by-itself)),
  for premium users, asks for the event's transcription (`/transcribe`)
  as soon as its image pages change; the Text view says it's on its way
  until the text comes. What the cloud writes counts as an automatic
  read (`tabTextAuto`): a text the user edited is never replaced.

**Upgrade offer** (on the web; the store apps leave it out, below):

- The account, on the [Profile](navigation.md#profile) tab, shows the
  user's role in the `tabscan` system under their name: **Role: Premium**,
  or **Role: Free** (everyone signed in; `premium` implies `free`), "Free
  (couldn't check)" when rbacr didn't answer, and "Checking…" before the
  first answer. It comes from the same status check as the card; builds
  without the service show no role.
- It also has a
  **TabScan Premium** card. For premium users: transcription is automatic, and until when.
  For others: what Premium does, "Subscribe with <their address>",
  **Upgrade** (the Substack subscribe page), **Redeem a voucher** (rbacr's
  page) and **Check again**. Signed out, it says Premium comes with
  signing in.
- The [event screen](event-screen.md) shows a dismissible hint, "TabScan
  Premium transcribes your scans automatically", with **Upgrade** (it opens
  the account, the Profile tab's panel, in a sheet), on events without a text tab, for users without
  Premium (signed out included).

**In the store apps** (Android and iOS: `storeApp` in
[premium_card.dart](../tabscan_app/lib/screens/premium_card.dart), not on
the web): App Store guidelines 3.1.1 and 3.1.3(b) and Google Play's
payments policy don't let an app point to buying a digital feature
outside the store, and Premium is sold on the web. So the apps show no
way to buy it: no Upgrade, no "Subscribe with <address>", no Redeem a
voucher and no event screen hint. Premium bought on the web still works
in them (multiplatform services): the role line, and for premium users
the card's "transcribed automatically" and until when, are as on the
web. A free user's card only says "TabScan Premium isn't active for
<address>.", with **Check again**. The account panel, the card and the
event screen take a `store` flag (null: the platform's), which the tests
set to check both.
- On the web without Premium, the Text view says reading tabs needs the
  Android or iOS app, or TabScan Premium.

## Troubleshooting log

- **App**: every call to the service is logged
  (`TabScan: OCR API: POST <url>`, then its status, time and answer, or
  the error); `TabScan: cloud OCR:` lines say when a read can't ask (no
  ID token, not premium), and, per sync pass, how many results were found,
  which events wait for which pages, each result's status, and whether the
  text tab was filled or kept.
- **Service** (CloudWatch, `aws logs tail /aws/lambda/tabscan-ocr-api
  --follow`, and `.../tabscan-ocr`): one JSON line per event. `http`: the
  path, status, time, identity, premium and the answer (the address left
  out), why a token was refused or a body was bad. `transcribe`: the
  event's files, those already transcribed, how many were queued and which
  files aren't page images. `s3 event`: the key and the outcome (an
  identity that never called `/account` is logged as such). `rbacr`: the
  answer and its ttl, or why the check failed (HTTP status). `ocr start`,
  `ocr done` (status, staves, lines, engine timings, seconds) and
  `ocr failed` (the exception and traceback, before Lambda retries).

## Infrastructure

- **`ocr-repo.yaml`**, stack `tabscan-ocr-repo`: the ECR repository
  `tabscan-ocr` (immutable tags, scanned on push, the last 10 images
  kept).
- **`ocr.yaml`**, stack `tabscan-ocr`:
  - the table `tabscan-accounts` (identity ID → address; on demand,
    point-in-time recovery); a user's item is deleted with their account,
    by the share API ([deleting the account](cloud-sync.md#deleting-the-account));
  - `tabscan-ocr` (3008 MB, the account's current cap; 5 min, one retry): it may get page images and put
    results;
  - `tabscan-ocr-api` (512 MB, 300 s for [auto-correct](autocorrect.md)'s
    `/autocorrect`; the other requests take a second or two): it may read
    and write the table, read the rbacr secret (and the Claude API key's,
    when set), invoke `tabscan-ocr`, list the bucket and delete results;
  - its function URL (no IAM auth: each request carries a Google ID token;
    CORS for the web app's origins, the local HTTPS one included);
  - the EventBridge rule `tabscan-ocr-pages` (page images created or
    deleted in the user-data bucket).
- **`user-data.yaml`** sends the bucket's events to EventBridge.
- Deployed by an administrator with
  [tabscan_locr/scripts/deploy.sh](../tabscan_locr/scripts/deploy.sh); its
  output URL is the app's `TABSCANNER_OCR_URL`. It passes the Claude API
  key's secret (`tabscan/anthropic-api-key`) when it exists.

## Verified

- Service unit tests (pytest): page keys parsed strictly; premium pages
  queued and free ones not; unknown identities aren't premium; deletions
  remove results; `/account` needs a good token and records the identity;
  `/transcribe` is premium-only and queues only untranscribed pages; rbacr's
  answer is cached by its ttl and fails closed; the pipeline finds lines,
  staves and widths, rebuilds lines and votes, and keeps the notations off
  the staves in their place (chord names at their columns, noise dropped).
- The image's build reads back a made-up riff (at least 80% of its notes,
  90% at the time of writing, counted on the tab lines) and the title
  above it (80% alike).
- App tests: a premium event gets its text tab once every page is read;
  pages without tab are left out; the user's edits stay; a text tab
  marked correct stays; a free user gets
  nothing; late pages are asked for once; the Premium card's upgrade offer
  and premium state; in a store app, no Upgrade, voucher or subscribe
  wording on the card and no event screen hint, while Premium (and until
  when) still shows.
- On a real photographed tab page (the OCR bench, kept out of git), the
  pipeline read 90% of the notes on macOS and 87.5% in the Linux image.

## Known limitations

- Text tabs only; typeset staves are left to on-device reading.
- No concurrency is reserved (the account's limit is 10); a burst of
  uploads queues.
- Results arrive at the next sync pass after they're written (up to a
  minute, plus about 30 s of OCR per page).
- Transcriptions of events deleted in the bucket by other means than the
  app (whole folders) stay until their pages' deletions reach the rule.
