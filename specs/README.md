# TabScan — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

TabScan is a camera app for guitar tabs, in the style of document scanner
apps (Adobe Scan, CamScanner), made for tablature. Point the phone at a tab
and it finds the page, straightens it and cleans it up. TabScan can then
read the tab into editable plain text and share it as a PDF, text or
images. Anyone can capture, signed out, and what they capture stays on
the device. Reading tabs and sharing need signing in (with Google), which
also syncs the user's events with the cloud, so they're on every device
the user signs in on. With TabScan Premium, scans are also transcribed in
the cloud as they sync.

## Features

**App**

- [Library](library.md): the home screen, a grid of events (newest first),
  with Scan, Import, Share and Delete; how events are stored.
- [Scanning](scanning.md): the system document scanner (edge detection,
  straightening, several pages), importing photos, and adding pages.
- [Event screen](event-screen.md): one event's pages (images, videos and
  links, with Open and Copy) to swipe and zoom, with
  Add page, Filter, Rotate, Read tab and Delete, plus Rename and Share.
- [Page filters](page-filters.md): Original, and Tab (black ink on white,
  by adaptive thresholding), the default.
- [Tab recognition](tab-recognition.md): Read tab, from on-device OCR to
  plain-text tab, for text tabs and typeset tab staves; the text tab
  editor.
- [Sharing](sharing.md): PDF, text (the text tab and links), or files
  (images and videos), through the system share sheet.
- [Sign-in and cloud sync](cloud-sync.md): optional Google sign-in from
  the library's cloud button; signed-in users' events sync both ways with
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
- [Deploy](deploy.md): the web app at https://tabscan.nu01.com and the
  release candidate at https://rc.tabscan.nu01.com.
