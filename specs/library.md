# Library

The home screen, titled **TabScan**.

- **Events** show as a grid of cards, newest first: the first image page's
  thumbnail (with its filter; a play badge for an event of only videos), the
  title, and a line with the artist (if set), the page count, the video
  count (if any), and "text" once the tab has been read. Tapping a
  card opens the [event screen](event-screen.md); its ⋮ menu has **Rename**,
  **Share** ([sharing](sharing.md)) and **Delete** (after a confirmation,
  which says the pages and text tab go too). Long-pressing a card renames
  it.
- **Empty**: a music icon, "No tabs yet", and a line saying what Scan does.
- **Scan** (floating button, bottom right) opens the
  [document scanner](scanning.md). The new event lands at the top of the
  list, which scrolls up to it, outlined in the theme's primary color for
  3 seconds, and a message confirms it ("Saved "Tab 2026-10-10 14:05" (2
  pages)") with **Open**. **Import photos** (app bar) does the same from
  photos on the device. **About**
  (app bar) shows the version (X.Y.Z, or "development build"). In a
  build with sign-in, the app bar's cloud button opens the account sheet
  ([sign-in and cloud sync](cloud-sync.md)); events synced from other
  devices appear in the list as they come down.
- **Theme**: Material 3, dark, from an amber seed color (`#E0A030`).

## Events

An **event** (`CaptureEvent` in the code; called a scan before it could
hold more than scanned pages) has an ID, a title, an artist (optional), when it was created,
when it last changed (`updated`: every change the user makes sets it;
older events count their creation), its pages, and the text tab once read.
Once it has synced it also has an `owner`, the Cognito identity it syncs
with (kept on the device only). A page has an ID, a kind (**image** or
**video**), its file's extension, and a [filter](page-filters.md) (used
for images only). A new event is titled `Tab YYYY-MM-DD HH:MM` (its local time).

**Rename** (a card's menu or long-press, or the event screen's title or
pencil) asks for the **Song** and **Artist**, prefilled, with the song's
text selected so typing replaces it. Saving with an empty song keeps the
title; an empty artist clears it. Exports are named from the new title
([sharing](sharing.md)).

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
image pages with the extension `img`.

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
