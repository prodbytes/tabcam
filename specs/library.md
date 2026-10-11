# Library

The **Home** tab ([navigation](navigation.md)), titled **TabScan**.

- **Events** show as a grid of cards, newest first: the first image page's
  thumbnail (with its filter; without images, a play badge if it has
  videos, or else a PDF icon, a music note for recordings, or a link
  icon; with them [hidden](hidden-images.md), a text icon once the tab
  is read, or else those badges), the title, and a line with the artist
  (if set), the page count ("images hidden" when they are), the video,
  recording, PDF and link counts (if any), "text"
  once the tab has been read, and "shared by <email>" for a capture
  someone [shared](shared-captures.md) with the user (whose menu has
  **Remove** instead of Delete, and no Rename when read only). Tapping a
  card opens the [event screen](event-screen.md); its ⋮ menu has **Rename**,
  **Share** ([sharing](sharing.md)), **Clone** (below) and **Delete** (after a confirmation,
  which says the pages and text tab go too). Long-pressing a card renames
  it.
- **Sections**: once something is shared with the user, Home has two
  headed sections, **My captures** (the user's own, or "Nothing of your
  own yet: go to Capture to add some." when there are none) and below it
  **Shared with me** (captures [shared](shared-captures.md) with the
  user), each newest first. With nothing shared, the grid has no
  headings.
- **Empty**: a music icon, "No tabs yet", and a line pointing to
  Capture (to scan, or add photos, videos, files and links).
- New events come from the [Capture](navigation.md#capture) tab: each
  lands at the top of the list, which scrolls up to it, outlined in the
  theme's primary color for 3 seconds, and a message confirms it
  ("Saved "Tab 2026-10-10 14:05" (2 pages)") with **Open**, for 6
  seconds. Events
  synced from other devices appear in the list as they come down.
- **Theme**: Material 3, dark, from an amber seed color (`#E0A030`).

## Events

An **event** (`CaptureEvent` in the code; called a scan before it could
hold more than scanned pages) has an ID, a title, an artist (optional), when it was created,
when it last changed (`updated`: every change the user makes sets it;
older events count their creation), its pages, and the text tab once read.
Once it has synced it also has an `owner`, the Cognito identity it syncs
with, and one shared with the user has `sharedBy` (the owner's email) and
`readOnly` (all kept on the device only). A page has an ID, a kind (**image**,
**video**, **audio**, **pdf** or **link**), its file's extension, and a
[filter](page-filters.md) (used for images only). A link has no file
(its extension is `url`): it has its address (`url`, `http` or `https`
only, checked again whenever an event is loaded, since events also come
from the cloud) and an optional `title`. A new event is titled `Tab YYYY-MM-DD HH:MM` (its local time).

**Rename** (a card's menu or long-press, or the event screen's title or
pencil) asks for the **Song** and **Artist**, prefilled, with the song's
text selected so typing replaces it. Saving with an empty song keeps the
title; an empty artist clears it. Exports are named from the new title
([sharing](sharing.md)).

**Clone** (a card's menu, or the event screen's app bar, which then opens
the copy) makes a copy that is a new event of the user's own: titled
"<title> (copy)", with the same artist, text tab and pages, each page a
new page with its file copied (links copied as they are), created now,
and never synced or shared yet. So it can be changed, or shared with
other people, apart from the original. A message says "Cloned as
"<title> (copy)"".

**Delete** removes an event and its pages. One that has synced leaves a
**tombstone** (its ID, `updated` and `deleted` times, no pages), hidden
from the list, so the deletion reaches the user's other devices; one that
never synced is gone at once.

**Rotate** stores the turned image as a new page (a new ID, same filter)
in the old one's place, and deletes the old file: page files never change
once written, which is what lets cloud sync compare pages by name.

IDs are the creation time in microseconds, base 36. IDs and extensions
(1–5 lower-case letters or digits) name files, so anything else (a path,
say) is refused when loading. Events saved before videos were added load as
image pages with the extension `img`. A kind this version doesn't know (from a newer app,
through the cloud) loads as an image page.

## Storage

- **Android and iOS**: files in the app's documents folder, one folder per
  event: `scans/<event id>/scan.json` (the details; the names are from
  before events were called scans, so existing libraries still load) and
  `<page id>.<extension>` per page: the image as scanned, or the photo or
  video as picked (copied file to file, never read whole into memory).
  Cloud sync's state is `cloudsync.json`, beside `scans/`; pages it
  downloads are written to `<page>.part` and renamed when complete. `scan.json` is written beside and renamed
  over, so a crash never leaves half a file. An event whose `scan.json`
  can't be read is skipped, not fatal.
- **Web**: in memory; events last until the tab is closed.

Filtered pages are rendered on demand and cached in memory.
