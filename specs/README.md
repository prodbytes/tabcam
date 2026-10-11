# TabScan — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

TabScan is a camera app for guitar tabs, in the style of document scanner
apps (Adobe Scan, CamScanner), made for tablature. Point the phone at a tab
and it finds the page, straightens it and cleans it up. TabScan can then
read the tab into editable plain text and share it as a link, a PDF,
text or a zip of its files. Anyone can capture, signed out, and what they capture stays on
the device. Reading tabs and sharing need signing in (with Google), which
also syncs the user's events with the cloud, so they're on every device
the user signs in on. With TabScan Premium, scans are also transcribed in
the cloud as they sync.

## Features

**App**

- [Navigation](navigation.md): as Presence's, a bottom navigation bar
  with Home (the events), Capture (Scan with the camera; Add photos &
  videos, files or a link) and Profile (the account, About).
- [Library](library.md): the Home tab, a grid of events (newest first),
  in My captures and Shared with me sections once something is shared, with Rename, Share, Clone and Delete; how events are stored.
- [Scanning](scanning.md): the system document scanner (edge detection,
  straightening, several pages), and adding pages, photos, videos, files
  and links.
- [Event screen](event-screen.md): one event's pages (images, videos and
  links, with Open and Copy) to swipe and zoom, with
  the view (Original, Scan or Text), Add, Rotate and Delete, plus Rename
  and Share.
- [Hidden images](hidden-images.md): the owner hides a capture's photos
  and scans, for everyone; it then shows only the text tab, videos and
  links, and exports leave the images out.
- [Page filters](page-filters.md): Original, and Tab (black ink on white,
  by adaptive thresholding), the default.
- [Tab recognition](tab-recognition.md): every capture read by itself
  into plain-text tab (on-device OCR, or Premium's cloud), for text tabs
  and typeset tab staves, never over the user's edits or a reading marked
  correct; the Text view, a tab editor (overtype, − and + on a fret)
  where a reading is marked correct (the event then opens on it).
- [Auto-correct](autocorrect.md): Fix, for Premium: Claude finds the
  song's tab online (tab sites first) and proposes corrections, which the
  user accepts or rejects note by note.
- [Sharing](sharing.md): a link to the capture (the default), PDF,
  text (the text tab and links), or a zip of everything, through the
  system share sheet; opening a capture's link.
- [Sign-in and cloud sync](cloud-sync.md): optional Google sign-in from
  the Profile tab; signed-in users' events sync both ways with
  their own folder in S3 (Cognito identity pool credentials, no server),
  deletions included.
- [Shared captures](shared-captures.md): share a capture of one's own
  by email, to edit (the default) or read only; no email is sent, people
  find it when they sign in. A share API (Lambda, DynamoDB, an HTTP API
  with a Google JWT authorizer) keeps the grants and hands out
  credentials for just that capture's folder.
- [TabScan Premium: cloud OCR](cloud-ocr.md): premium users' pages
  transcribed in AWS Lambda as they sync (Tesseract, PaddleOCR and
  RapidOCR per string line, voted), the text tab filled in by itself;
  premium is rbacr's `tabscan/premium` role (Substack subscription or
  voucher); the upgrade offer for everyone else.
- [App icon](app-icon.md): a scanned tab page with a staff and fret
  numbers, in scanner corners; how the platform icons are generated.
- [Platforms](platforms.md): Android, iOS and the web, and what each can do.
- [Maintenance mode](maintenance-mode.md): administrators switch it on
  with `scripts/maintenance.sh`; the apps then show only a sorry message.

**Development and operations**

- [Development environment](dev-environment.md): devbox, the dev
  container, `devbox services up` and the health monitor, the run scripts.
- [Release builds](release.md): versions, tags and the Release workflow.
- [App stores](app-stores.md): publishing to Google Play and the App
  Store under personal accounts: the status of each step, the Android
  upload key and App Bundle.
- [Deploy](deploy.md): the web app at https://tabscan.nu01.com and the
  release candidate at https://rc.tabscan.nu01.com.
