# Navigation

As in Presence: a **bottom navigation bar** flips between full-screen
tabs, and a compact **app bar** on top names the open one
([lib/screens/home_screen.dart](../tabcam_app/lib/screens/home_screen.dart)).

- **Bottom navigation bar** (a Material `NavigationBar`): one destination
  per tab, an icon over its label, in order:
  - **Home**: the events ([library](library.md)).
  - **Capture**: makes a new event (below).
  - **Profile**: the account ([sign-in and cloud sync](cloud-sync.md#signing-in))
    and About. Signed in with a Google photo, its icon is that photo
    (24 dp), ringed in the accent color while open, with the tooltip
    "Signed in as <name> · <email>"; otherwise a person icon.
  - The open tab is marked by color only: its icon filled and its label
    bold, both in the theme's primary (amber); the others outlined, in
    the secondary text color; no pill behind the icon. Flat, 64 dp, every
    label shown, a hairline above it (the theme's `navigationBarTheme`).
  - Signed in only (signed out, there's only the welcome, below); tabs
    keep their state (the list's scroll) while another is open.
- **App bar**: the open tab's name on the left, bold (22 sp, weight 700):
  "TabCam" on Home, "Capture", "Profile". No buttons: what was there
  (Import photos, About, the cloud button) is on the tabs.
- An event opens over the tabs as its own screen ([event screen](event-screen.md)),
  with a back button.

## Signed out: the welcome

In a build with sign-in, a user who isn't signed in sees only the
**welcome** ([lib/screens/welcome_screen.dart](../tabcam_app/lib/screens/welcome_screen.dart)):
TabCam's name, what it does and that signing in starts it ("your
captures are kept on every device you sign in on"), the sign-in buttons
(Google's, and Apple's where it's offered), a sign-in error under them,
a progress line while a saved session is restored at launch, and
**Privacy policy**. No tabs, no Capture, no Profile: TabCam's features
are for signed-in users, except a capture's link with its key: it opens
that capture, read only, instead of the welcome, with **Sign in** to go to
the welcome ([opening a link](sharing.md#opening-a-link)). Signing in opens
Home (where a capture's link, opened signed out, then opens); signing out
goes back to the welcome.
Captures already on the device stay there, and are the user's once they
sign in. A build without sign-in set up has no welcome: the app is as it
was, on the device only.

## Coming back where the user was

A reload (the web) or a restart (the apps) opens where the user was:
the tab, and the event that was open over it, on its Text view or its
list of files, and the file open over that, if one was
([lib/screens/place.dart](../tabcam_app/lib/screens/place.dart)).
The place is kept on the device (the library's `place` meta file, not
synced), saved half a second after each move: switching tabs, opening
or closing an event, switching Files and Text, opening or closing a
file. A capture's link opening at launch wins over it; an event deleted
since isn't
opened.

## Capture

- **Scan**, a large button: the camera, through the
  [document camera](scanning.md) (it finds, straightens and cleans the
  page, several in a row; on the web, TabCam's camera screen), with a
  line saying so. Document opens the file chooser for PDFs, Photos &
  videos the photo album, Files the file chooser, Link the link dialog.
- **Add**, for uploads, each a card:
  - **Document**, first: PDF files (the file chooser offering only
    `.pdf`); each PDF is a page the event screen shows as the document;
  - **Photos & videos**: from the photo library;
  - **Files**: image and video files;
  - **Link** ("A lesson, a backing track, a video"): an address and an
    optional title, which then also names the event
    ([adding](scanning.md#adding-to-an-event) has the details).
- Under them, the note on whose tabs go in TabCam (`OwnTabsNote`, only
  here, where tabs are added; not on Home): "TabCam is for musicians practicing with their own tabs. Only add what you have the right to use: tabs you wrote, your teacher's, ones you bought, or ones free to share."

Each makes a new event. Its title: an upload (Document, Photos &
videos, Files, or files dropped on Capture), the name of the first file
picked that has a real one, without its extension (`Lesson 3 - alternate
picking.mp4` is "Lesson 3 - alternate picking"; a zip's own name, not its
files'); a Link, its title; else (a Scan, or only made-up names)
`Tab YYYY-MM-DD HH:MM`. A made-up name is a picker's or a camera's
(`MediaPick.madeUpName`): `image_picker_…` (photos from the iOS photo
library), `IMG_1234`, `VID_20261030_101500`, `VID-…-WA0001`, `PXL_…`,
`Screenshot … at …`, a date and time, digits, a UUID. A video from the
photo library keeps its name on Android, iOS and the web, so a lesson's
names its capture. It goes to **Home**, where it's first in the list, scrolled to
and outlined for 3 seconds, with a message, "Saved "<title>" (2 pages)"
(or "1 video, 1 link", ...), and **Open**, which goes by itself after 6
seconds, as every message does (Flutter would otherwise keep a message
with a button until it's dismissed). Cancelling does nothing;
picked files that aren't photos or videos are left out, with a message
saying how many.

**Dragging files** (from the desktop or a file manager) onto the Capture
tab makes a new event of them, as **Files** does: while they're over it,
it's outlined with "Drop files to add"; dropped folders are left out
with the others. On the web, macOS, Windows, Linux and Android
(`desktop_drop`; [FileDropArea](../tabcam_app/lib/screens/file_drop_area.dart)),
not iOS.

## Profile

The account, up to 560 dp wide: signed out, **Sign in** with what it's
for and the sign-in button; signed in, who (and, with Premium set up,
their [profile](profiles.md#in-the-app): "Profile: huge_wavy_darter",
its roles, and **Linked accounts**; without profiles, the role, "Role:
Premium" or "Role: Free"), the sync status, **Sync now**
and **Sign out** ([sign-in and cloud sync](cloud-sync.md#signing-in)),
and with Premium set up the **TabCam Premium** card
([cloud OCR](cloud-ocr.md)), then **Delete account**, which asks first
and deletes the account in the cloud and on the device
([cloud sync](cloud-sync.md#deleting-the-account)); opening the tab checks
again whether the user is premium (the store apps leave out the card's
upgrade offer, [cloud OCR](cloud-ocr.md#in-the-app)). The same panel opens
in a sheet from an event's Premium **Upgrade** (on the web). In
a build without sign-in, a line says so. Then **Language**
([localization](localization.md)): the device's language (the default),
English, Español or Português; the app changes at once. Then **About**: the app's name
and version (X.Y.Z, or "(development build)"), what it does,
**Privacy policy** (opens https://tabcam.nu01.com/privacy in the browser,
[privacy](privacy.md)) and **Licenses**.
Last, until TabCam is in the app stores, **Get the phone app**: "TabCam
isn't in the app stores yet", and **iPhone** and **Android** links, each
opening a sheet with how to install it from GitHub
([release](release.md#installing-a-release)):

- **Android**: on the phone, open the latest release, download its
  `-android.apk`, allow the browser to install apps the first time, and
  Install (or Update, keeping the events); Google sign-in doesn't work in
  these builds yet. **Open the release on GitHub** opens
  https://github.com/prodbytes/tabcam/releases/latest.
- **iPhone**: the release's iOS app is unsigned, so it's built on a Mac
  with Xcode and Flutter and signed with the user's own Apple account
  (Developer Mode on, trusting the developer the first time; a free
  account's build stops opening after 7 days). **Open the guide on
  GitHub** opens the README's iOS steps.

Only on the web and desktop: the store apps leave it out (the same
binaries go to the stores, which don't allow pointing to other installs).
[install_links.dart](../tabcam_app/lib/screens/install_links.dart).
