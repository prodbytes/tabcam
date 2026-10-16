# TabCam — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

TabCam is a camera app for guitar tabs, in the style of document scanner
apps (Adobe Scan, CamScanner), made for tablature. Point the phone at a tab
and it finds the page, straightens it and cleans it up. TabCam can then
read the tab into editable plain text and share it as a read-only link
(and download a zip of its files). Signed out, the app is a welcome and the
sign-in buttons only; everything else is for signed-in users (with
Google, or with Apple on iOS). Signing in
also syncs the user's events with the cloud, so they're on every device
the user signs in on. With TabCam Premium, scans are also transcribed in
the cloud as they sync.

## Features

**App**

- [Navigation](navigation.md): as Presence's, a bottom navigation bar
  with Home (the events), Capture (Scan with the camera; Add a
  document (PDF), photos & videos, files or a link) and Profile (the account, About).
- [Library](library.md): the Home tab, a grid of events (newest first),
  in My captures and Shared with me sections once something is shared, with Rename, Share, Clone and Delete; how events are stored.
- [Scanning](scanning.md): the system document scanner (edge detection,
  straightening, several pages), and adding pages, photos, videos, files
  and links.
- [Tab site links](tab-site-links.md): a link to a known tab site
  (Ultimate Guitar, Songsterr, Cifra Club, LaCuerda...) is also imported
  as a PDF print of its page, read for tab; fetched on the device (on the
  web, by the cloud, for Premium only).
- [Event screen](event-screen.md): one event's files (images, videos,
  recordings, PDFs and links) as a list with previews, Files, Text and
  Add and Cam (the list reorders in place by drag handles), plus Rename,
  Clone and one Share; a tap opens a file alone, with
  its view (Original or Scan), Rotate and Delete.
- [Cam](cam.md): record yourself playing along with the tab: the camera,
  the tab under it one neckline (staff) at a time, any key to the next
  and Backspace / ← / ↑ to the one before, or a strong nod up / right and
  down / left (Android, iOS); Rec adds each take to the
  capture, Play plays it back with the tab turning as it did; Play
  along plays one of the capture's recordings, videos or links in a
  frame above the camera, the space bar pausing and playing it.
- [Hidden images](hidden-images.md): the owner hides a capture's photos
  and scans, for everyone; it then shows only the text tab, videos and
  links, and exports leave the images out.
- [Page filters](page-filters.md): Original, and Tab (black ink on white,
  by adaptive thresholding), the default.
- [Tab recognition](tab-recognition.md): every capture read by itself
  into plain-text tab with the page's chords, lyrics and section names
  (on-device OCR, or Premium's cloud), for text tabs
  and typeset tab staves, never over the user's edits or a reading marked
  correct; the Text view, a tab editor (Copy, Rescan and Verified
  on one line; overtype, − and + on a fret, ++ and −− moving a note across strings) where a reading is marked
  verified (the event then opens on it).
- [Auto-correct](autocorrect.md): Fix, **hidden for now** (on only in a
  build with `TABCAM_FIX=true`): lines the tab up, and for Premium Claude
  finds the song's tab online (tab sites first) and proposes corrections,
  which the user accepts or rejects note by note.
- [Sharing](sharing.md): Share copies the capture's link, nothing
  else; opening a capture's link.
- [Sign-in and cloud sync](cloud-sync.md): optional Google sign-in (and
  Sign in with Apple on iOS) from the Profile tab; signed-in users' events sync both ways with
  their own folder in S3 (Cognito identity pool credentials, no server),
  deletions included; Delete account deletes it all.
- [Caching users' files](cdn.md): every object says how to cache it
  (pages a year, JSON revalidated); reads go through the site's
  CloudFront, signed per folder by the share API, and a device cache keeps
  them as the same headers say (files on phones, IndexedDB on the web).
- [Profiles](profiles.md): as in Presence, a user's data belongs to a
  profile (`huge_wavy_darter`), made at their first sign-in; Google and
  Apple accounts link to it with a code (or by the same verified address),
  reach the same captures, and give it all their roles.
- [Encryption at rest](encryption.md): each profile has an RSA key pair
  (its private key wrapped by one KMS key); each capture its own AES-256
  key, wrapped with the profile's public key; the API unwraps it for the
  owner, the people it's shared with and its link's holders.
- [Shared captures](shared-captures.md): share a capture of one's own
  by email, to edit (the default) or read (see and add one's own files); no email is sent, people
  find it when they sign in. A share API (Lambda, DynamoDB, an HTTP API
  with Google and Apple JWT authorizers) keeps the grants and hands out
  credentials for just that capture's folder.
- [Contributions](contributions.md): who sees which files of a shared
  capture. Readers, and people who join by its link signed in, add files
  of their own that only they and the owner see; the owner publishes the
  ones they like into the capture, for everyone; signed out, a link shows
  the owner's files only.
- [TabCam Premium: cloud OCR](cloud-ocr.md): premium users' pages
  transcribed in AWS Lambda as they sync (Tesseract, PaddleOCR and
  RapidOCR per string line, voted), the text tab filled in by itself;
  premium is rbacr's `tabcam/premium` role (Substack subscription or
  voucher); the upgrade offer for everyone else, on the web only (the
  store apps show no purchase links).
- [Localization](localization.md): the app in English, Spanish and
  Portuguese, the device's language by default or one picked on the
  Profile tab.
- [App icon](app-icon.md): a scanned tab page with a staff and fret
  numbers, in scanner corners; how the platform icons are generated.
- [Platforms](platforms.md): Android, iOS and the web, and what each can do.
- [Privacy](privacy.md): the privacy policy at
  https://tabcam.nu01.com/privacy (linked from the index page and About),
  what it says and what it's based on; the iOS privacy manifest and
  export compliance declaration.
- [Maintenance mode](maintenance-mode.md): administrators switch it on
  with `scripts/maintenance.sh`; the apps then show only a sorry message.

**Development and operations**

- [Development environment](dev-environment.md): devbox, the dev
  container, `devbox services up` and the health monitor, the run scripts.
- [Release builds](release.md): versions, tags and the Release workflow.
- [App stores](app-stores.md): publishing to Google Play and the App
  Store under personal accounts: the status of each step, the Android
  upload key and App Bundle, the store listings in `tabcam_store/` and
  their upload to App Store Connect with fastlane, TestFlight.
- [Deploy](deploy.md): the web app at https://tabcam.nu01.com and the
  release candidate at https://rc.tabcam.nu01.com.
