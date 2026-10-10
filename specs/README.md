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
images. Everything happens on the device. Signing in (with Google) is
optional: it syncs the user's scans with the cloud, so they're on every
device the user signs in on; signed out, nothing leaves the device.

## Features

**App**

- [Library](library.md): the home screen, a grid of scans (newest first),
  with Scan, Import, Share and Delete; how scans are stored.
- [Scanning](scanning.md): the system document scanner (edge detection,
  straightening, several pages), importing photos, and adding pages.
- [Scan screen](scan-screen.md): one scan's pages to swipe and zoom, with
  Add page, Filter, Rotate, Read tab and Delete, plus Rename and Share.
- [Page filters](page-filters.md): Original, and Tab (black ink on white,
  by adaptive thresholding), the default.
- [Tab recognition](tab-recognition.md): Read tab, from on-device OCR to
  plain-text tab, for text tabs and typeset tab staves; the text tab
  editor.
- [Sharing](sharing.md): PDF, text tab, or images, through the system
  share sheet.
- [Sign-in and cloud sync](cloud-sync.md): optional Google sign-in from
  the library's cloud button; signed-in users' scans sync both ways with
  their own folder in S3 (Cognito identity pool credentials, no server),
  deletions included.
- [App icon](app-icon.md): a scanned tab page with a staff and fret
  numbers, in scanner corners; how the platform icons are generated.
- [Platforms](platforms.md): Android, iOS and the web, and what each can do.

**Development and operations**

- [Development environment](dev-environment.md): devbox, the dev
  container, `devbox services up` and the health monitor, the run scripts.
- [Release builds](release.md): versions, tags and the Release workflow.
- [Deploy](deploy.md): the web app at https://tabscan.nu01.com and the
  release candidate at https://rc.tabscan.nu01.com.
