# TabCam — software specification

The current specification of the product, one file per feature. Update the
feature files a request changes, and add a file when a request adds a
feature. [requests.md](requests.md) holds the history of requests that shaped
it.

## Product

TabCam is a camera app for guitar tabs, in the style of document camera
apps (Adobe Scan, CamScanner), made for tablature. Point the phone at a tab
and it finds the page, straightens it and cleans it up. TabCam can then
read the tab into editable plain text and share it as a read-only link
(and download a zip of its files). Signed out, the app is a welcome and the
sign-in buttons only; everything else is for signed-in users (with
Google, or with Apple on iOS). Signing in
also syncs the user's events with the cloud, so they're on every device
the user signs in on. With TabCam Premium, scans are also transcribed in
the cloud as they sync.

**Who it's for**: musicians practicing with their own tabs (tabs they
wrote, their teacher's lesson sheets, books and printouts they bought,
tabs free to share). TabCam comes with no songs, tabs, sheet music or
lyrics and fetches none: everything in it is what its users capture or
add, in their own accounts, and they must have the right to use it. The
app says so where content is added ([library](library.md),
[Capture](navigation.md#capture)), and so do the store listings and
review notes ([app stores](app-stores.md)).

## Features

**App**

- [Navigation](navigation.md): as Presence's, a bottom navigation bar
  with Home (the events), Capture (Scan with the camera; Add a
  document (PDF), photos & videos, files or a link) and Profile (the account, About, and how to install the phone app from GitHub).
- [Library](library.md): the Home tab, a grid of events (newest first),
  in My captures and Shared with me sections once something is shared, with Rename, Share, Clone and Delete; how events are stored.
- [Scanning](scanning.md): the system document camera (edge detection,
  straightening, several pages), and adding pages, photos, videos, files
  and links.
- [Tab site links](tab-site-links.md): in the web app and on desktops
  (not the store apps), a link to a known tab site
  (Ultimate Guitar, Songsterr, Cifra Club, LaCuerda...) is also imported
  as a PDF print of its page, read for tab; fetched on the device (on the
  web, by the cloud, for Premium only).
- [Studies](studies.md): an optional study per capture, to group related
  ones, set from the open capture's rename dialog; Home's study chips
  (only once one is set) show one study's captures.
- [Event screen](event-screen.md): one event's files (images, videos,
  recordings, PDFs and links) as a list with previews, Files, Text and
  Add and Cam (the list reorders in place by drag handles), plus Rename,
  Clone and one Share; a tap opens a file alone, with
  its view (Original or Scan), Rotate and Delete, the play-along
  sidebar beside an image or a PDF, and a recording playing in it with
  the capture's pages and PDFs to follow beside. Text and Cam are
  Premium's: locked, each opens as a preview under the Premium card.
- [Cam](cam.md): record yourself playing along with the tab: the camera,
  the tab under it one neckline (staff) at a time, any key (↓) to the
  next and Backspace / ↑ (← with nothing playing along) to the one before, or a strong nod up / right and
  down / left (Android, iOS); Rec adds each take to the
  capture, Play plays it back with the tab turning as it did; Play
  along plays one of the capture's recordings, videos or links in a
  frame above the camera, the space bar pausing and playing it, 0
  going back to its start (its section's) and ← / → skipping in it,
  play waiting a 2-second count-in (shown in amber on the progress
  bar's line, with a button to turn it off); turns
  of the tab while recording along with a song are kept as that file's
  own phrase passes (marked on its player, merged within two seconds at their
  average time), and **Auto-pass** turns the tab there the next time
  through.
- [Dictionary](dictionary.md): a book icon at the top of every file
  viewer and Cam opens a search in a sidebar on the right: a chord shows
  its notes and voicings as chord diagrams, a scale its notes on the
  fretboard (both worked out on the device); anything else is searched
  on YouTube. Every sidebar (the dictionary, the metronome, the
  play-along player) is resizable by dragging its edge, the width kept on
  the device.
- [Metronome](metronome.md): a stopwatch icon beside the dictionary's
  opens a metronome in a sidebar: 80 BPM in 4/4 by default, the tempo set
  with −, + and a slider (30–250), the common time signatures (2/4 to
  12/8), a light per beat, Start / Stop; clicks made on the device (Web
  Audio on the web, a looping WAV on the phones), accented on the bar.
- [Video edit](video-edit.md): basic edits of a video from its file
  screen: trim its start and end; keep its sound, take it out, or
  replace it with a new track (one of the capture's recordings, or a
  sound file, added to them), shifted to fit the video. The edit is kept
  with the video and played as it says (muted, the track along it), no
  file made; Download makes one on the device: the video, the video
  without sound, or the sound only.
- [Hidden images](hidden-images.md): the owner hides a capture's photos
  and scans, for everyone; it then shows only the text tab, videos and
  links, and exports leave the images out.
- [Page filters](page-filters.md): Original, and Tab (black ink on white,
  by adaptive thresholding), the default.
- [Tab recognition](tab-recognition.md): every capture read by itself
  into plain-text tab with the page's chords, lyrics and section names
  (Premium's cloud; on-device OCR in builds without the service; nothing
  without Premium), for text tabs
  and typeset tab staves, never over the user's edits or a reading marked
  correct; the Text view, a tab editor (Copy, Rescan and Verified
  in the app bar, the editing tools on their own line; overtype first, − and + on a fret, ++ and −− moving a note across strings, | a bar line and = a spacer dash down the phrase, |> and <| ending every phrase's lines together at the last or the first end, New phrase an empty six-line phrase) where a reading is marked
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
- [Sign-in sessions](sessions.md): TabCam's own session (the share API's
  refresh token and KMS-signed ID tokens) keeps the user signed in until
  they sign out or leave it unused for a week (90 days at most), whatever
  the provider's hour-long token does.
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
- [TabCam Premium: Text, Cam and cloud OCR](cloud-ocr.md): Text and
  Cam are Premium's (locked, they open as previews under the Premium
  card, with the offer); premium users' pages
  transcribed in AWS Lambda as they sync (Tesseract, PaddleOCR and
  RapidOCR per string line, voted), the text tab filled in by itself;
  premium is rbacr's `tabcam/premium` role (Substack subscription or
  voucher); the offer, Home's banner and the card on every platform, the
  store apps included.
- [Localization](localization.md): the app in English, Spanish and
  Portuguese, the device's language by default or one picked on the
  Profile tab.
- [App icon](app-icon.md): a scanned tab page with a staff and fret
  numbers, in camera corners; how the platform icons are generated.
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
