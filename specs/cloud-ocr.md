# TabCam Premium: Text, Cam and cloud OCR

TabCam Premium is the [event screen](event-screen.md)'s **Text** and
**Cam**: the text tab ([tab recognition](tab-recognition.md), the pages
read into it by itself, on the device or in the cloud) and recording
oneself playing along ([Cam](cam.md)); it also removes the **watermark**
the [video editor](video-edit.md#layers) puts on a downloaded video
("Recorded by TabCam", "Made with TabCam"). Premium users' scans are
**transcribed in the cloud as they sync**: the event's text tab appears
by itself, read more accurately than on the phone, and on the web too.
Without Premium, nothing is read, and Text and Cam open as **previews**
(the screen as it would be, greyed out, taking nothing) under the
Premium card, which says what the feature is and how to subscribe
([in the app](#in-the-app)). The service is
[tabcam_locr/](../tabcam_locr/README.md), two AWS Lambda functions.

A build has Premium only with [cloud sync](cloud-sync.md) set up and
`TABCAM_OCR_URL` (the service's function URL) set. Without it the app is
as before, and nothing is locked: Text and Cam are open to everyone
(local builds without the service, and the tests). `premiumLocked(ocr)` in
[premium_card.dart](../tabcam_app/lib/screens/premium_card.dart) is the
rule: the service is set up and the user isn't premium. The watermark's
rule beside it, `watermarkUnlocked(ocr)`, is the other way round: no
service, or the user has Premium now (`CloudOcr.premiumNow`, below).

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
   `cached: true`. Read again never uses it. Queueing a page also writes
   a marker beside its result, `<identity>/ocr/<event id>/<page
   id>.reading`: while it's younger than the worker's 15-minute timeout,
   `/transcribe` (Read again too) doesn't queue the page a second time.
3. `tabcam-ocr` reads the page and writes
   `<identity>/ocr/<event id>/<page id>.json`:
   `{page, status, text, doubts, staves, lines, seconds, engines, version,
   created}`, `status` being `ok`, `no-tab` or `error`; `doubts` the notes
   read with little confidence, likely wrong, `[[line, column, note]]` in
   `text` (lines and columns from 0; see [doubtful notes](#doubtful-notes));
   `engines` the OCR engines, or the vision model's ID when it read the
   tab ([handwriting](#handwriting-read-by-a-vision-model)), with its
   `agreement`.
   A page deleted while it was read gets no result (the worker checks it's
   still there before writing). Read, gone or failed, the marker is
   removed.
4. Deleting a page (or its event) in the bucket deletes its transcription
   and its marker.

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
- A page the [vision model](#handwriting-read-by-a-vision-model) read has
  none: the model says nothing of how sure it is.

On the bench's three pages (158 notes) 21 notes were doubtful, 9 of them
wrong; of the 16 wrong notes, 9 were doubtful. Of the 7 not flagged, 4 only
had a vibrato of another length (`5~~` for `5~`), and 3 were numbers lost
or joined before reading (a circle touching a fret), which no score sees.

The title, section names and chord names around the staves are read at
full size, each strip between staves on its own and the whole page too
(each finds words the other misses), and placed as for text tabs; other apps'
watermarks ("Digitalizado com CamScanner", "Scanned with ...") are left
out, in the app too. Printed numbers read exactly (the image's build reads
a made-up riff set on drawn lines back, every note). Handwriting the
engines read poorly: 62% to 90% of the frets on four pages, with no bar
line, slide or slur ([measured 2026-11-13](#verified-captures)), so a
handwritten page is read by a vision model too (below).

### Handwriting read by a vision model

A page on drawn staves whose reading by the engines is unsure, more than
a tenth of its frets [doubtful](#doubtful-notes) (`UNSURE`: handwriting
had from a fifth to two thirds, on the pages measured; print reads sure),
is also read whole by a vision model on Amazon Bedrock
([locr/vision.py](../tabcam_locr/locr/vision.py)): **Moonshot AI's Kimi
K3.1** (`us.moonshotai.kimi-k3.1`, the stack's `VisionModel`; the one
model the account can call that reads these pages: Claude 5 isn't
granted to it, [verified captures](#verified-captures)). Printed pages,
tabs on dash lines and pages the engines find no tab on aren't sent
(the last only with `VISION_BLANK=1`).

- **What it gets**: the page as it came (a PDF's page as rendered), at
  most 1600 px wide and 2400 px high, as a JPEG, and a prompt on how
  handwritten tabs are read (the strings top to bottom, the staircase of
  a run across strings, two digits close together being one fret, the
  string numbers at the staff's start not being notes, slides, slurs,
  bends, vibrato, bar lines, show-through from the back of the sheet left
  out) and the output's format. It thinks first, with most of its
  `maxTokens` (16000, `VISION_MAX_TOKENS`: it reads worse with less), and
  answers with the tab, or `NO TAB`.
- **On Bedrock's flex tier** (`VisionTier`, `flex`): half the default
  tier's price, for the same model. On the four pages (13 readings,
  2026-11-13) it read as well as the default tier (93.7% of the frets a
  reading, 96.1% keeping the closer of two; the default's 92.7% and
  94.7%), as fast (about 52 s), and was never turned away. It's served
  last when Bedrock is busy, so a reading flex turns away (a throttle,
  unavailable) goes to the default tier at once, then waits out
  throttles there (below). A smaller thinking budget, the other way to
  spend less, read worse: at 8000 `maxTokens`, 86.8% a reading and 31% at
  worst, 92.3% and 78% keeping the closer of two.
- **Twice, side by side** (`VisionReads`, 2): its readings of a page vary
  (79% to 99% of the frets right, one in 25 at 56%, its notes on the
  wrong strings), so it reads the page twice at once and the reading
  closest to the engines' is kept: the share of its frets, by string and
  number in the order they're played, the engines' reading has too
  (`agreement`, in the result). The engines' reading is mostly right
  where it's sure, and a reading gone wrong agrees with it least. Over the
  readings measured, keeping the closer of two read 93.5% of the frets on
  average and 82% at worst, against 91% and 56% for one reading.
- **Its answer** becomes the text tab: each staff's lines made one length
  and closed by a bar, a bar line on some of a staff's lines put across
  the staff, staves without notes left out, the title, section names and
  repeat marks above their staves (noise left out as for the engines'
  [notations](#transcription)). It has no doubtful notes.
- **The engines' reading stands** when the model's answers aren't whole
  (cut short at `maxTokens`, no tab, fewer than half the engines' frets),
  or when it fails: a throttle (the account's 1M tokens a minute for the
  profile: each reading reserves its 16000, so about a dozen at once) is
  waited out, 20, 40 then 60 s (and up to 10 s more), the worker having
  15 minutes; another error is logged (`vision failed`). No reading starts
  that couldn't end (180 s, its timeout) before the worker's time runs out,
  less 30 s to write the result (a long PDF whose engines' reading took
  most of it): the engines' reading is written instead.
- **A PDF's** handwritten pages are read by the model five at a time,
  after the engines have read them all; the PDF's `agreement` is its
  least.
- **Time and cost**: a reading takes about 55 s (the engines' reading of
  the page before it, 15 to 50 s); a page is about 5.3k tokens in and
  12.4k out, the output (its thinking) nine tenths of the cost. At Kimi
  K3's flex price ($1.65 and $8.25 a million tokens, half its default
  tier's; K3.1 isn't in the price list yet) about $0.11 a reading, $0.22
  a page read twice ($0.44 on the default tier), against $0.0044 for the
  engines. Only Premium pages are
  read (the worker reads nothing else), and a page read before isn't
  read again ([its cached result](#transcription)).
- **Measured** with the image's code on the four handwritten pages
  (2026-11-13; two readings each, real engines, Kimi K3.1): 95%, 84%,
  89% and 98% of the frets right, against 71%, 62%, 83% and 90% for the
  engines; the printed photo wasn't sent (97%, the engines').
- **Privacy**: Bedrock keeps no prompts or answers and shares none with
  the model's maker; through the `us.` profile a page may be read in
  N. Virginia, Ohio or Oregon ([privacy](privacy.md)).

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
  issued for the bundle ID `com.nu01.tabcam`), or, with `SESSION_ISSUER`
  set, a [TabCam session](sessions.md)'s (signed by its KMS key, the keys
  at the share API's `/session/.well-known/jwks.json`, for `tabcam-app`,
  taken as the sign-in that started the session); either way unexpired,
  with a verified address. It asks the main identity pool for the token's
  identity ID, under the issuer's `Logins` key (so local web builds, whose
  identities are in the local pool, get 401), records identity → address,
  and answers `{email, premium, expiresAt, checked, upgradeUrl,
  voucherUrl}`. An Apple token while the service has no `APPLE_CLIENT_ID`
  gets 403 `google sign-in needed`, and the card says "Premium needs
  Google sign-in".
- **Results**: after each sync pass, a premium user's app lists
  `<identity>/ocr/`. Once every image page of one of their synced events
  has a result, the `ok` texts, in page order and separated by a blank
  line, each after a divider with its file's name when there are two or
  more ([several files](tab-recognition.md#several-files): joined on the
  device, the server untouched), become the event's text tab, which then syncs like any change. It
  writes the text tab only while it's empty or still the text it wrote
  (kept in `cloudocr.json`), and not marked correct, so it never replaces
  the user's edits, an on-device reading or a checked text tab. New pages update it the same way.
  The pages' `doubts` come with it, moved down by the lines of the pages
  before, the blank lines between them and the dividers, as the event's
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
- **Warm-up**: opening the camera (Scan, on Home or in an event), a
  premium user's app calls `POST /warm`, and the service has a worker
  load its engines (`{"warm": true}`), so the pages about to come skip
  the cold start ([speed](#speed)). At most one per user every 5
  minutes (per service container), Premium only (402 otherwise); a
  failure is only logged. Each costs about 15 s of the worker (a few
  hundredths of a cent).
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

<a id="in-the-app"></a>**In the app** (the same on every platform, the store apps
included):

- **Locked tools**: without Premium, the event screen's **Text** and
  **Cam** tools carry a small lock on their icon (tooltip "Text: TabCam
  Premium", "Cam: TabCam Premium"). Each still opens: Text shows the
  [Text view](tab-recognition.md#text-view) as a **preview**, the
  capture's own text if it has one, else a made-up sample tab (captioned
  "A preview with a sample tab"), greyed out and taking no tap or key,
  with no play-along sidebar; Cam opens its screen the same way, with no
  camera (a camera icon in its place), the capture's tab or the sample
  along the bottom, and Rec, Play and the arrows dead. Over the preview,
  centred, the **Premium card** (`PremiumGate`): the lock, "TabCam
  Premium", what the feature is ("Text is part of TabCam Premium: your
  scans read into a text tab you can edit, copy, verify, download and
  play along with…"; "Cam is part of TabCam Premium: record yourself
  playing along…"), the offer and its buttons (below), and **Not now**,
  which goes back to the files (or leaves Cam). Signed out (a capture
  opened by its link), the card says to sign in, then subscribe from the
  profile, with no buttons. A capture whose text is marked correct opens
  on the files, not the Text view, for a locked user.
- **Home's banner**: signed in without Premium, Home starts with "Text
  tabs and Cam are TabCam Premium features." with **Upgrade** (the
  account sheet, with the card) and a close that keeps it away until the
  app restarts. It waits for the first Premium check, so premium users
  never see it flash.
- **Nothing is read** by itself without Premium ([tab
  recognition](tab-recognition.md#reading-by-itself)): the reading waits
  and starts once the user has it.
- **The video editor's watermark** ([video edit](video-edit.md#layers)):
  without Premium its chip is locked on, and a tap opens the Premium
  card in a sheet, starting with "Premium removes the watermark"; with
  it, the chip turns it off. Whether it's left out is decided for the
  one downloading, at Download: an edit a Premium user made without it
  still has it when someone without Premium downloads it. For this,
  the app keeps the service's last answer on the device (the meta
  `premium`: the account's ID, the answer and when; in localStorage on
  the web), and `premiumNow` is the service's answer, or, until it has
  answered (offline, say) or when it couldn't check, that last answer
  for the same account, if it's at most a week old. The editor listens,
  so an answer arriving while it's open unlocks the chip in place.

**Upgrade offer** (everywhere, the store apps included):

- The account, on the [Profile](navigation.md#profile) tab, shows the
  user's role in the `tabcam` system under their name: **Role: Premium**,
  or **Role: Free** (everyone signed in; `premium` implies `free`), "Free
  (couldn't check)" when rbacr didn't answer, and "Checking…" before the
  first answer. It comes from the same status check as the card; builds
  without the service show no role.
- It also has a
  **TabCam Premium** card (`PremiumCard`), the same card the locked tools
  show over their previews. For premium users: "Text tabs and Cam are
  yours: your scans are transcribed in the cloud as they sync…", and
  until when. For others: the offer, "Read your scans into text tabs,
  transcribed automatically in the cloud, and record yourself playing
  along with Cam. $10 a month or $100 a year: subscribe with <their
  address>." (US$ in es and pt), **Upgrade** (the service's `upgradeUrl`:
  the Substack subscribe page, whose checkout is Stripe's), **Redeem a
  voucher** (rbacr's page) and **Check again**. Signed out, the account
  says Premium comes with signing in.

<a id="in-the-store-apps"></a>**In the store apps** (Android and iOS): since 2026-11-03 the
offer is the same as on the web (the user's decision: the apps say what
is Premium and how to subscribe, by the Stripe-backed link, as in-app
purchases through the App Store or Google Play aren't built). Before,
the apps hid every purchase link and, for free users, every mention of
Premium (App Review had taken "TabCam Premium isn't active" for a broken
in-app purchase, guideline 2.1(b), 2026-10-20), and the account panel,
the card and the event screen took a `store` flag; that flag is gone
(`storeApp` now only hides the install links, [navigation](navigation.md#profile)).
**Review risk**: an iOS app that links to buying a digital feature
outside the App Store is under guideline 3.1.1 (external purchase links
are allowed in the US storefront after the 2025 Epic ruling, and in the
EU under the alternative terms, not elsewhere), and Google Play's
payments policy has the same rule, so the next store submissions may
need App Store and Play Billing subscriptions, or the link hidden again
in those builds ([app stores](app-stores.md)).

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
  `vision read` (the model, whether it found a tab, its frets, tokens in
  and out, the service tier that served it, seconds) for each reading by
  the vision model, `vision
  failed` (the error) when one fails.
  `transcribe` also counts the pages left alone because they're being
  read (`reading`). `ocr engines loaded` (seconds: a cold start), `ocr
  warm` (a warm-up: whether it loaded the engines, and how long it
  took), and `ocr page gone` (deleted before or while it was read: no
  result written).

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
    images, put results, delete `.reading` markers and list the bucket
    (so a page deleted meanwhile answers 404, not 403), and, with
    `VisionModel` set, invoke that inference profile and its model only
    through it (`VISION_MODEL`, `VISION_READS`, `VISION_TIER`); no longer the Claude API
    key's secret, which only auto-correct uses;
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
  key's secret (`tabcam/anthropic-api-key`) when it exists. Deployed, it
  invokes `tabcam-ocr` once with `{"warm": true}` (see
  [speed](#speed)), so the first page after a deploy doesn't wait for
  the new image.

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

### Speed

Measured on 2026-10-21 from the worker's logs (33 readings, 2026-10-16
to 10-21) and a local profile of three of the developer's handwritten
pages:

- **A page takes 60 to 200 s**, warm or cold: almost all of it is the
  reading. On drawn staves (handwriting), about 60% is the fret numbers
  (80 to 210 per page, each read by PaddleOCR's recognizer, RapidOCR's
  when that isn't a fret) and 30% the words around the staves (RapidOCR,
  about 10 calls per page). Lambda reads about 5 times slower than an
  Apple M-series laptop: about 1.5 vCPUs at 2560 MB, and Paddle's oneDNN
  acceleration off (it fails on x86 with Paddle 3.3).
- **A cold start** (a new worker loading the models) adds 6 to 14 s; the
  first after a new image adds 80 to 120 s (Lambda fetching the image),
  hence the warm-up after each deploy.
- Reading the numbers with PaddleOCR's recognizer alone, in batches (no
  detection), was tried: no faster (51 s vs 55 s for 430 numbers, the
  model itself is the cost), and 46 of them read differently. Not taken.
- **Keeping a worker always warm** (provisioned concurrency) costs about
  $27 a month per 2560 MB worker, against the [design
  guideline](../CLAUDE.md) of spending little on servers: not done.
- **Measured in Lambda** ([bench.sh](../tabcam_locr/scripts/bench.sh):
  a temporary function from the image reads pages already in the
  bucket, writing nothing; 2560 MB, warm), on three handwritten pages:
  PaddleOCR with its default 8 threads, 59, 131 and 90 s; with one
  thread per CPU (2), **48, 90 and 65 s, the same text**: now the
  default (`cpu_threads`, the CPU count; `LOCR_CPU_THREADS` overrides
  it). oneDNN (`LOCR_MKLDNN=1`) still fails in Lambda
  ("ConvertPirAttribute2RuntimeAttribute not support"), with
  `FLAGS_enable_pir_api=0` too: it stays off.
- **More CPU** (Lambda's memory, capped at 3008 MB on this account until
  its limits are raised; 10240 MB brings 6 vCPUs): to measure once the
  limit is raised.

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

### Verified captures

<a id="verified-captures"></a>Measured 2026-11-13 on the two captures
whose text the user marked **Verified** (scanned handwritten pages in
marker, one page each, 87 and 95 frets; kept in `test_data/verified`, out
of git: published songs), each fret scored by its string and its order
against the verified text. No code changed.

| Reader | Page 1 | Page 2 |
|---|---|---|
| Cloud OCR as deployed (its stored results) | 71% | 62% |
| Claude Opus 4.6 on Bedrock, the whole page | 68% | 51% |
| Claude Opus 4.6, with thinking | 67% | 66% |
| Claude Sonnet 4.6, the whole page | 33% | 49% |
| Claude Opus 5.5, the whole page | 99% | 100% |
| Claude Sonnet 5.5, the whole page | 94% | 97% |
| Kimi K3.1 on Bedrock, the whole page | 93% | 89% |
| Kimi K3 | 76% | 0% |
| Claude Opus 4.5 | 68% | 35% |
| Kimi K2.5, Nova Pro, Mistral Large 3, Magistral Small | 23% to 38% | 0% to 40% |
| Qwen3-VL, Gemma 3 27B, Ministral 14B, Nova 2 Lite, Nova Lite, Claude Haiku 4.5, Pixtral Large, Nemotron Nano | under 25% | under 25% |

- **The cloud OCR's 61 wrong frets**: 20 phantoms (string numbers at the
  staff's start, the brace and "2x" at its end, print showing through
  from the back of the sheet), 17 misread (12 of them a 10, 12 or 13 read
  as 0, 1, 3 or 6), 13 missed and 11 on the wrong string. It reads no bar
  line (8 on the pages) and no slide or slur (25).
- **Claude 4.6** reads the digits (1 to 5 misread a page) but puts them on
  the wrong strings (16 to 79 a page), as on the bench on 2026-11-07.
- **Claude 5.5** was run as a Claude Code subagent given the page image
  (1600 px wide) and the reading prompt only, not through Bedrock: every
  Claude 5 model still answers "not available for this account" there
  (the Opus 5.5 quota requests of 2026-10-29 are pending). Opus 5.5's one
  miss is a note the user added that isn't on the page; it also wrote the
  bar lines and the slides.
- **The other Bedrock models** (every one that takes an image and
  answers for this account, one reading each, the same prompt): only
  **Kimi K3.1** (Moonshot, `us.moonshotai.kimi-k3.1`) reads the pages,
  with the slides and slurs (its bar lines only on the string that has
  the notes). The rest put the notes on
  the wrong strings (Kimi K3 put a whole page two strings down) or miss
  most of them. Not available for the account, as Claude 5: every OpenAI
  GPT (5.4 to 6.1), Grok 4.6 and 4.7, GLM 5.3; Llama 4 is refused by
  country, Nova Premier is at its end of life.
- **Kimi K3.1 again**, three readings each of the two pages and of the
  bench's two handwritten ones (35 and 42 frets): 89, 98, 99%; 86, 89,
  96%; 89, 89, 94%; 95, 98, 98% (the cloud OCR: 71, 62, 83, 90%). It
  thinks before it answers, with about 78% of `maxTokens`, and reads
  worse with less: about 93% of the frets at 16000, 91% at 8000, 79% at
  4000 and 70% at 2000. A page is 5.2k tokens in and, at 16000, 12.4k
  out in about 55 s: about $0.22 a page at Kimi K3's list price ($3.30
  and $16.50 a million tokens; K3.1's isn't listed yet), $0.12 at 8000,
  against $0.0044 for the cloud OCR.

## Known limitations

- Handwritten numbers written into each other ("12" touching "10") are
  read as one; a section letter's circle touching a fret takes it.
- No concurrency is reserved, and the account's limit is 10 (an increase
  to 1000 was requested on 2026-10-21); a burst of uploads queues.
- Results arrive at the next sync pass after they're written (up to a
  minute), plus 60 to 200 s of OCR per page ([speed](#speed)).
- Transcriptions of events deleted in the bucket by other means than the
  app (whole folders) stay until their pages' deletions reach the rule.
