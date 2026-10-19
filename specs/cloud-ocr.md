# TabCam Premium: cloud OCR

Premium users' scans are **transcribed in the cloud as they sync**: the
event's text tab appears by itself, read more accurately than on the
phone, and on the web too. Free users keep [on-device reading](tab-recognition.md)
and, on the web, are offered the upgrade. The service is
[tabcam_locr/](../tabcam_locr/README.md), two AWS Lambda functions.

A build has Premium only with [cloud sync](cloud-sync.md) set up and
`TABCAM_OCR_URL` (the service's function URL) set. Without it the app is
as before.

## Who is premium

[rbacr](https://github.com/prodbytes/rbacr) decides: the role `premium`
in its `tabcam` system (`premium` implies `free`), for the user's verified
addresses: every account linked to their [profile](profiles.md#roles)
(Google, or Apple on iOS); premium if any of them is. The service finds
the request's profile in the share API's tables (`PROFILES_TABLE`,
`SUBJECTS_TABLE`, read only), records its folder with all its addresses,
and for uploads checks those addresses; a sign-in without a profile is
checked by its own address, as before. People get it by:

- **Subscribing** to prodbytes.substack.com, at **US$10 a month or US$100
  a year** (the prices are set in Substack's payment settings, not in
  code), with the same Google address:
  rbacr's Stripe sync grants the `tabcam` system's subscriber role,
  `premium`, for the paid period.
- **A voucher**, redeemed on rbacr's own page (https://rbacr.nu01.com/me,
  signing in with Google).
- A root's grant in rbacr.

**Signed in with Apple**, the address is the one in Apple's ID token: the
user's own if they shared it, which is premium like anyone's; Apple's
private relay address if they hid it, which matches no subscription or
voucher (unless rbacr grants that address), so it isn't premium. The card
then says Premium goes by address and that their relay address has none:
to use Premium under their own address, sign in with Google, or with Apple
sharing it. An address is only trusted when the provider says it's
verified (Apple's `email_verified` is the string `"true"`).

The service asks rbacr (`POST /api/check`) with a root-owned API token kept
in SSM Parameter Store (the standard-tier SecureString
`/tabcam/rbacr-token`, under the AWS-managed `aws/ssm` key), never in the
app; each container reads it once. If rbacr
can't answer, the user is not premium for now. A "yes" is trusted for at
most 5 minutes (less if the grant ends sooner), a "no" for 1 minute.

## Transcription

1. Cloud sync uploads a page image (`.img`, `.jpg`, `.jpeg`, `.png`,
   `.webp`) or a PDF (`.pdf`) to `<identity>/events/<event id>/`. The bucket sends the
   upload to EventBridge, which calls `tabcam-ocr-api`.
2. It looks up the identity's verified address (recorded by `/account`,
   below), asks rbacr, and for premium users invokes `tabcam-ocr`.
   Free users' pages stop there. An image read before (the same content:
   a clone, a published contribution, the same file added again) isn't
   read again: the reading kept by its S3 ETag
   (`<identity>/ocrcache/<ETag>-<version>.json`, written by `tabcam-ocr`
   for `ok` and `no-tab` readings) is copied as the page's result, with
   `cached: true`. Read again never uses it.
3. `tabcam-ocr` reads the page and writes
   `<identity>/ocr/<event id>/<page id>.json`:
   `{page, status, text, doubts, staves, lines, seconds, engines, version,
   created}`, `status` being `ok`, `no-tab` or `error`; `doubts` the notes
   read with little confidence, likely wrong, `[[line, column, note]]` in
   `text` (lines and columns from 0; see [doubtful notes](#doubtful-notes)).
4. Deleting a page (or its event) in the bucket deletes its transcription.

**Reading a page**: the page is found and flattened if it's a photo; red
ink is dropped (the red channel, then whatever is still red, not dark,
becomes paper, so no grey ghost of a red pen stays over the notes); the
light is evened out; a page tilted half a degree or more is levelled (the
angle, within 4 degrees, at which its rows of ink are sharpest; turning
blurs fine strokes, so a page nearly level is left as is); and it's scaled
to 2800 px. Each tab string line is a row of dashes a column apart (flat
marks that aren't evenly spaced, such as a drawn line a poor scan broke
up, aren't one): they're found, grouped into staves (six lines
`e B G D A E`, four `G D A E`; fewer than four isn't a staff), and each
line is cut out and read by Tesseract (one line, tab characters only),
PaddleOCR and RapidOCR. Each word goes at the column its position implies,
measured alike on every line of a staff (from the staff's first dash, the
median of where its lines' dashes start, in its median column width).
Then the ink itself says where the notes are: on the line's strip, the
marks that aren't dashes (nor the label, the bars or specks), grouped by
gaps of most of a column, are its notes; when a reading has as many
tokens as the strip has notes, each token goes at its note's column. The
engines drop and double dashes, so the columns they imply drift (by up to
30 on a long line); the ink's don't, and a chord's notes share a column.
Per line, the reading closest to the other two (fewest token edits
between dashes) wins. A staff's lines end together: trailing dashes
trimmed, then all padded with dashes to the staff's width (or to the line
whose notes go furthest).

**PDFs** are read as if their pages were photographed: each page (at most
10) is rendered on white, 2000 px wide (PDFium, `pypdfium2`), and read as
a photo is (below); the pages' tabs are joined by a blank line into the
PDF's one result. The image's build reads the made-up riff from a PDF of
its photo too.

**Tabs on drawn staff lines** (handwritten, or typeset: books, Guitar Pro
printouts), where the frets sit on the lines and there are no dashes, are
read by the same engines another way ([locr/staves.py](../tabcam_locr/locr/staves.py)),
when a page has no dash lines:

1. Long horizontal strokes are the staff lines (a scan's thin lines come
   dotted: the gaps are bridged first; a slightly skewed or bowed line,
   rows a few pixels apart, is one); lines about a gap apart, six (four
   for bass, five where the page cuts the last), make a staff.
2. The lines are erased, except where a pen stroke crosses them, so the
   numbers stay whole.
3. The ink near each staff (reaching further above the top line than
   below the bottom one: handwritten frets often sit above their line) is
   split into marks of a digit's size. A digit the line cut in pieces one
   above the other (a 3 through its middle) is one mark again; flat
   strokes (slurs, a brace's tail) are left out. Marks side by side at
   about the same height are one number, on the string nearest its
   middle. Marks at the staff's start, within a line gap of it
   (handwritten string numbers, the TAB clef), are left out.
4. Each number's crop is read by PaddleOCR's recognizer, or RapidOCR's
   (no detection) when that isn't a fret: PaddleOCR read handwritten
   digits best. On a page written with a fine pen (strokes under a tenth
   of a line gap) the crops are made a little bolder first. Misreadings
   are fixed (S 5, $ 5, g 9, o 0, l 1, B 8, C 6, ...); a read of several
   ("5 7-9", "5(6)5") is split across the crop, and a "number" past fret
   24 (55, 97) is two notes.
5. Numbers about the same x are one column (a chord); columns get dashes
   before them by their distance, as the app lays out a typeset tab.

### Doubtful notes

Each result says which of its notes were read with little confidence,
likely wrong (`doubts`), for the app to show them in red:

- **Tab lines** (dashes): a note of the winning reading that neither other
  engine has (their tokens aligned by edits) is doubtful: the engines
  don't agree on it. With one engine only, nothing is.
- **Drawn staves**: a number is doubtful when PaddleOCR's score for it is
  under 0.8 (`CROP_SURE`), or when only RapidOCR read it as a fret. Also
  asking the two to agree flagged more right notes (RapidOCR reads
  handwritten 6s and 8s as letters) and no more wrong ones.
- A PDF's doubts count the lines of the pages before (and the blank line
  between them).

On the bench's three pages (158 notes) 21 notes were doubtful, 9 of them
wrong; of the 16 wrong notes, 9 were doubtful. Of the 7 not flagged, 4 only
had a vibrato of another length (`5~~` for `5~`), and 3 were numbers lost
or joined before reading (a circle touching a fret), which no score sees.

The title, section names and chord names around the staves are read at
full size, each strip between staves on its own and the whole page too
(each finds words the other misses), and placed as for text tabs; other apps'
watermarks ("Digitalizado com CamScanner", "Scanned with ...") are left
out, in the app too. Printed numbers read exactly (the image's build reads
a made-up riff set on drawn lines back, every note); handwriting from
about 80% to 90% of the notes right, in order and on the right string, on
the bench's two handwritten pages (crowded pages, numbers written into
each other, less), so the text is worth checking against the page.

Claude (vision, [locr/vision.py](../tabcam_locr/locr/vision.py)) can
read the pages nothing else does, but it's **off**: on only with
`VISION_FALLBACK=1` on the function and the Claude API key
(`tabcam/anthropic-api-key`), neither set.

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

`CloudOcr` ([lib/cloud/cloud_ocr.dart](../tabcam_app/lib/cloud/cloud_ocr.dart)):

- **Status**: at sign-in, and each time the Profile tab (or the account
  sheet, from an event's Upgrade on the web) opens, the app
  calls `POST /account` with the user's ID token. The service checks the
  token, by its issuer: Google's (signed by Google, issued for TabCam's
  web client or the local web client) or, with `APPLE_CLIENT_ID` set,
  Apple's (signed by Apple's keys, `https://appleid.apple.com/auth/keys`,
  issued for the bundle ID `com.nu01.tabcam`); either way unexpired, with
  a verified address. It asks the main identity pool for the token's
  identity ID, under the issuer's `Logins` key (so local web builds, whose
  identities are in the local pool, get 401), records identity → address,
  and answers `{email, premium, expiresAt, checked, upgradeUrl,
  voucherUrl}`. An Apple token while the service has no `APPLE_CLIENT_ID`
  gets 403 `google sign-in needed`, and the card says "Premium needs
  Google sign-in".
- **Results**: after each sync pass, a premium user's app lists
  `<identity>/ocr/`. Once every image page of one of their synced events
  has a result, the `ok` texts, in page order and separated by a blank
  line, become the event's text tab, which then syncs like any change. It
  writes the text tab only while it's empty or still the text it wrote
  (kept in `cloudocr.json`), and not marked correct, so it never replaces
  the user's edits, an on-device reading or a checked text tab. New pages update it the same way.
  The pages' `doubts` come with it, moved down by the lines of the pages
  before and the blank lines between them, as the event's
  `tabTextDoubts`; a doubt whose note isn't at its place in the text is
  dropped.
- **Read again** (the Text view, or the Text tool tapped on it; also while
  the text is on its way from the cloud): `POST /transcribe {eventId,
  again: true}` reads every page again, results or not. The app first
  notes each page's result ETag, and fills the text tab only once every
  page's result is a new one (each result has the time it was made, so a
  rewrite always changes it); the earlier results don't count as the new
  reading. That text replaces any text tab a read left (`tabTextAuto`,
  on-device readings too), never the user's edits or a checked one.
- **Rescan** (the Text view's): a Read again whose reading, once every
  page's result is new, replaces the text tab whatever it is, the user's
  edits and a verified one too (`transcribe(event, again: true,
  replace: true)`), clearing Verified. A reading with no tab on any page
  leaves the text as it was.
- **Collected**: `CloudOcr.collected(eventId)` completes once an event's
  results are applied (a tab found, or none), so the reader stops saying
  it's in the cloud.
- **Pages from before upgrading**: an event whose pages still lack results
  20 minutes after its last change (past the OCR worker's 15-minute
  timeout, so pages still being read aren't queued again) is sent to
  `POST /transcribe {eventId}` (once per event per session), which queues
  its untranscribed pages.
- **Reading by itself** ([tab recognition](tab-recognition.md#reading-by-itself)),
  for premium users, waits for the event's transcription when an event
  without a text tab gets new pages: their uploads start it (step 1), so
  the app doesn't ask `/transcribe` too (that read pages being read a
  second time); the Text view says
  it's on its way until the text comes, or for at most three times the
  OCR worker's timeout, when it says reading failed. What the cloud writes counts as an automatic
  read (`tabTextAuto`): a text the user edited is never replaced.

**Upgrade offer** (on the web; the store apps leave it out, below):

- The account, on the [Profile](navigation.md#profile) tab, shows the
  user's role in the `tabcam` system under their name: **Role: Premium**,
  or **Role: Free** (everyone signed in; `premium` implies `free`), "Free
  (couldn't check)" when rbacr didn't answer, and "Checking…" before the
  first answer. It comes from the same status check as the card; builds
  without the service show no role.
- It also has a
  **TabCam Premium** card. For premium users: transcription is automatic, and until when.
  For others: what Premium does, its price and "subscribe with <their
  address>" ("$10 a month or $100 a year: subscribe with …"; US$ in es
  and pt),
  **Upgrade** (the Substack subscribe page), **Redeem a voucher** (rbacr's
  page) and **Check again**. Signed out, it says Premium comes with
  signing in.
- The [event screen](event-screen.md) shows a dismissible hint, "TabCam
  Premium transcribes your scans automatically", with **Upgrade** (it opens
  the account, the Profile tab's panel, in a sheet), on events without a text tab, for users without
  Premium (signed out included).

**In the store apps** (Android and iOS: `storeApp` in
[premium_card.dart](../tabcam_app/lib/screens/premium_card.dart), not on
the web): App Store guidelines 3.1.1 and 3.1.3(b) and Google Play's
payments policy don't let an app point to buying a digital feature
outside the store, and Premium is sold on the web. So the apps show no
way to buy it: no Upgrade, no "Subscribe with <address>", no Redeem a
voucher and no event screen hint. Premium bought on the web still works
in them (multiplatform services): the role line, and for premium users
the card's "transcribed automatically" and until when, are as on the
web. A free user's card only says "TabCam Premium isn't active for
<address>.", with **Check again**. The account panel, the card and the
event screen take a `store` flag (null: the platform's), which the tests
set to check both.
- On the web without Premium, the Text view says reading tabs needs the
  Android or iOS app, or TabCam Premium.

### Tab sites' pages for the web

`POST /page {url}` ([tabcam_locr/locr/pages.py](../tabcam_locr/locr/pages.py)),
**Premium only** (402 otherwise): the web app can't fetch other sites'
pages (CORS), so the service fetches a [tab site link](tab-site-links.md)'s
page for it and answers `{url, contentType, html}`, the page as text (by
its charset, else UTF-8). Android and iOS fetch pages on the device and
never call it. Only the tab sites' domains (`TAB_SITES`, the app's list),
over `http` or `https`, on the default port, without user or password,
and redirects (at most 5) only to them; anything else is 400 ("a tab
site's page needed"), and a redirect elsewhere, an HTTP error, a timeout
(15 s) or a page over 2 MB is 502 ("couldn't fetch the page"). The `http`
log line has the address and the page's size, not the page. The app asks
with `CloudOcr.fetchPage` (`OcrApi.page`), its log line the size only.

## Troubleshooting log

- **App**: every call to the service is logged
  (`TabCam: OCR API: POST <url>`, then its status, time and answer, or
  the error); `TabCam: cloud OCR:` lines say when a read can't ask (no
  ID token, not premium), and, per sync pass, how many results were found,
  which events wait for which pages, each result's status, and whether the
  text tab was filled or kept.
- **Service** (CloudWatch, `aws logs tail /aws/lambda/tabcam-ocr-api
  --follow`, and `.../tabcam-ocr`): one JSON line per event. `http`: the
  path, status, time, identity, premium and the answer (the address left
  out), why a token was refused or a body was bad. `transcribe`: the
  event's files, those already transcribed, how many were queued and which
  files aren't page images. `s3 event`: the key and the outcome (an
  identity that never called `/account` is logged as such). `rbacr`: the
  answer and its ttl, or why the check failed (HTTP status). `ocr start`,
  `ocr done` (status, staves, lines, engine timings, seconds) and
  `ocr failed` (the exception and traceback, before Lambda retries).

## Infrastructure

- **`ocr-repo.yaml`**, stack `tabcam-ocr-repo`: the ECR repository
  `tabcam-ocr` (immutable tags, scanned on push, the last 3 images
  kept: each is several GB).
- **`ocr.yaml`**, stack `tabcam-ocr`:
  - the table `tabcam-accounts` (identity ID → address; on demand,
    point-in-time recovery); a user's item is deleted with their account,
    by the share API ([deleting the account](cloud-sync.md#deleting-the-account));
  - `tabcam-ocr` (x86_64, like `tabcam-ocr-api`: one image, and
    PaddlePaddle has no working Linux ARM build of its version; 2560 MB,
    chosen by [measuring](#memory); 15 min, one retry): it may get page
    images and put results;
  - `tabcam-ocr-api` (512 MB, 300 s for [auto-correct](autocorrect.md)'s
    `/autocorrect`; the other requests take a second or two, `/page` up to
    15 s): it may read
    and write the table, read the rbacr token's parameter (and the Claude
    API key's secret, when set), invoke `tabcam-ocr`, list the bucket and delete results;
  - its function URL (no IAM auth: each request carries an ID token,
    Google's or Apple's (`AppleClientId`, the function's `APPLE_CLIENT_ID`);
    CORS for the web app's origins, the local HTTPS one included);
  - the EventBridge rule `tabcam-ocr-pages` (page images created or
    deleted in the user-data bucket).
- **`user-data.yaml`** sends the bucket's events to EventBridge.
- Deployed by an administrator with
  [tabcam_locr/scripts/deploy.sh](../tabcam_locr/scripts/deploy.sh); its
  output URL is the app's `TABCAM_OCR_URL`. It passes the Claude API
  key's secret (`tabcam/anthropic-api-key`) when it exists.

### Memory

`tabcam-ocr`'s memory was measured on 2026-10-16 by invoking it directly
on the image build's made-up riff photo (`selftest.page_photo()`, two
staves) under a made-up identity: at each size one cold invoke, then 3
to 6 warm ones (image `51473691cf23`, x86_64, us-east-1). The three
engines run side by side, so a page is CPU bound, and Lambda's CPU grows
with memory. The account caps a function's memory at 3008 MB, so the
sweep stops there; a page peaks at about 2 GB, so less than 2048 MB
isn't an option.

| Memory | Warm (median) | Cold invoke (init) | Billed GB-s | Per 1000 pages |
|---|---|---|---|---|
| 2048 MB | 143.7 s | 160.7 s (0.55 s) | 287.5 | $4.79 |
| **2560 MB** | **105.5 s** | 128.8 s (0.11 s) | **263.8** | **$4.40** |
| 3008 MB | 97.5 s | 106.2 s (0.21 s) | 286.3 | $4.77 |

Cold invoke: the first after a configuration change, which loads the
engines' models; init: Lambda's Init Duration. Cost: $0.0000166667 per
GB-s plus $0.20 per million requests. **2560 MB** is the sweet spot: the
cheapest per page, 8% less than 3008 MB for 8% more time (under the 10%
a step up must buy); 2048 MB is both slower and dearer, its ~1.95 GB
peak close to its limit. Measure again if the quota is raised: up to
10240 MB brings up to 6 vCPUs.

## Verified

- `/page` (pytest, a made-up page, a fake opener): the tab sites and their
  subdomains taken; other hosts, look-alikes, ports, credentials, `file:`,
  the metadata address and overlong addresses refused, and redirects off
  the sites; decoded by charset; capped at 2 MB; HTTP errors 502; Premium
  only; a bad body 400 without fetching; the log has the size, not the
  page.
- Service unit tests (pytest): page keys parsed strictly; premium pages
  queued and free ones not; unknown identities aren't premium; deletions
  remove results; `/account` needs a good token and records the identity;
  tokens of every listed Google client are taken, others refused; Apple's
  tokens (made up, signed with a test key) are taken for the bundle ID with
  `email_verified` a string or a boolean, and refused unverified, without
  an email, for another audience or signed by another key; without an
  Apple client they're "google sign-in needed" (403); other issuers are
  refused; an Apple user is their own identity, premium by their (relay)
  address;
  `/transcribe` is premium-only and queues only untranscribed pages; rbacr's
  answer is cached by its ttl and fails closed; its token is read once
  from the SSM parameter, decrypted, and an unreadable one fails closed; the pipeline finds lines,
  staves and widths, rebuilds lines and votes, and keeps the notations off
  the staves in their place (chord names at their columns, noise dropped).
- The image's build reads back a made-up riff (at least 80% of its notes,
  90% in the image at the time of writing, counted on the tab lines) and the title
  above it (80% alike).
- App tests: a premium event gets its text tab once every page is read;
  pages without tab are left out; the user's edits stay; a text tab
  marked correct stays; a free user gets
  nothing; late pages are asked for once; the Premium card's upgrade offer
  and premium state; in a store app, no Upgrade, voucher or subscribe
  wording on the card and no event screen hint, while Premium (and until
  when) still shows; an Apple user with a relay address is labelled by
  Apple and told Premium goes by address; "Premium needs Google sign-in"
  when the service takes no Apple tokens.
- The OCR bench (`test_data/ocr_bench`, kept out of git: published
  songs) scores each note by its string, its order and, on printed tabs,
  its column, against hand transcriptions. On macOS: a photographed
  printed tab with red ink across it, 90% of the notes (95% counting
  any vibrato run as one), every one in its column (77.5% and 90% before
  the red ghost was removed and the columns came from the ink); a
  scanned handwritten page in marker, 82.9% (none before: a drawn line in
  pieces passed for a row of dashes); a handwritten intro in fine pen,
  88.1% (42.9% before).
- In the Linux image the made-up riff's photo reads as before (90%),
  its PDF better (95%, from 90%), its drawn staves every note. A wider
  margin round the red ink read the real photo better (92.5%) but took
  the edges of the riff's digits under its red stroke (85%).
- Tried on the bench and left out, each worse than the pipeline: CLAHE,
  sharpening, Sauvola binarization or a 1.5x upscale of the line strips;
  erasing the dashes before the engines read; cutting the string label
  off the strip (Tesseract then reads dashes as `~`); pages at 2400 or
  3200 px; a vertical close of the erased ink; Tesseract on handwritten
  digits.

## Known limitations

- Handwritten numbers written into each other ("12" touching "10") are
  read as one; a section letter's circle touching a fret takes it.
- No concurrency is reserved (the account's limit is 10); a burst of
  uploads queues.
- Results arrive at the next sync pass after they're written (up to a
  minute, plus about 105 s of OCR per page, [measured](#memory) on a
  two-staff page).
- Transcriptions of events deleted in the bucket by other means than the
  app (whole folders) stay until their pages' deletions reach the rule.
