# Navigation

As in Presence: a **bottom navigation bar** flips between full-screen
tabs, and a compact **app bar** on top names the open one
([lib/screens/home_screen.dart](../tabscan_app/lib/screens/home_screen.dart)).

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
  - Shown signed in and signed out alike; tabs keep their state (the
    list's scroll) while another is open.
- **App bar**: the open tab's name on the left, bold (22 sp, weight 700):
  "TabScan" on Home, "Capture", "Profile". No buttons: what was there
  (Import photos, About, the cloud button) is on the tabs.
- An event opens over the tabs as its own screen ([event screen](event-screen.md)),
  with a back button.

## Capture

- **Scan**, a large button: the camera, through the
  [document scanner](scanning.md) (it finds, straightens and cleans the
  page, several in a row; on the web, TabScan's camera screen), with a
  line saying so. Photos & videos opens the photo album, Files the file
  chooser, Link the link dialog.
- **Add**, for uploads, each a card:
  - **Photos & videos**: from the photo library;
  - **Files**: image and video files;
  - **Link**: an address and an optional title, which then also names the
    event ([adding](scanning.md#adding-to-an-event) has the details).

Each makes a new event (titled `Tab YYYY-MM-DD HH:MM`, or a link's
title) and goes to **Home**, where it's first in the list, scrolled to
and outlined for 3 seconds, with a message, "Saved "<title>" (2 pages)"
(or "1 video, 1 link", ...), and **Open**, which goes by itself after 6
seconds, as every message does (Flutter would otherwise keep a message
with a button until it's dismissed). Cancelling does nothing;
picked files that aren't photos or videos are left out, with a message
saying how many.

## Profile

The account, up to 560 dp wide: signed out, **Sign in** with what it's
for and the sign-in button; signed in, who (and, with Premium set up,
their role: "Role: Premium" or "Role: Free"), the sync status, **Sync now**
and **Sign out** ([sign-in and cloud sync](cloud-sync.md#signing-in)),
and with Premium set up the **TabScan Premium** card
([cloud OCR](cloud-ocr.md)); opening the tab checks again whether the
user is premium. The same panel opens in a sheet from an event's Premium
**Upgrade**. In
a build without sign-in, a line says so. Then **About**: the app's name
and version (X.Y.Z, or "(development build)"), what it does,
**Privacy policy** (opens https://tabscan.nu01.com/privacy in the browser,
[privacy](privacy.md)) and **Licenses**.
