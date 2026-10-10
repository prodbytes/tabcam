# Library

The home screen, titled **TabScan**.

- **Scans** show as a grid of cards, newest first: the first image page's
  thumbnail (with its filter; a play badge for a scan of only videos), the
  title, and a line with the artist (if set), the page count, the video
  count (if any), and "text" once the tab has been read. Tapping a
  card opens the [scan screen](scan-screen.md); its ⋮ menu has **Rename**,
  **Share** ([sharing](sharing.md)) and **Delete** (after a confirmation,
  which says the pages and text tab go too). Long-pressing a card renames
  it.
- **Empty**: a music icon, "No tabs yet", and a line saying what Scan does.
- **Scan** (floating button, bottom right) opens the
  [document scanner](scanning.md). The new scan lands at the top of the
  list, which scrolls up to it, outlined in the theme's primary color for
  3 seconds, and a message confirms it ("Saved "Tab 2026-10-10 14:05" (2
  pages)") with **Open**. **Import photos** (app bar) does the same from
  photos on the device. **About**
  (app bar) shows the version (X.Y.Z, or "development build").
- **Theme**: Material 3, dark, from an amber seed color (`#E0A030`).

## Scans

A scan has an ID, a title, an artist (optional), when it was created, its
pages, and the text tab once read. A page has an ID, a kind (**image** or
**video**), its file's extension, and a [filter](page-filters.md) (used
for images only). A new scan is titled `Tab YYYY-MM-DD HH:MM` (its local time).

**Rename** (a card's menu or long-press, or the scan screen's title or
pencil) asks for the **Song** and **Artist**, prefilled, with the song's
text selected so typing replaces it. Saving with an empty song keeps the
title; an empty artist clears it. Exports are named from the new title
([sharing](sharing.md)).

IDs are the creation time in microseconds, base 36. IDs and extensions
(1–5 lower-case letters or digits) name files, so anything else (a path,
say) is refused when loading. Scans saved before videos were added load as
image pages with the extension `img`.

## Storage

- **Android and iOS**: files in the app's documents folder, one folder per
  scan: `scans/<scan id>/scan.json` (the details) and
  `<page id>.<extension>` per page: the image as scanned, or the photo or
  video as picked (copied file to file, never read whole into memory). `scan.json` is written beside and renamed
  over, so a crash never leaves half a file. A scan whose `scan.json`
  can't be read is skipped, not fatal.
- **Web**: in memory; scans last until the tab is closed.

Filtered pages are rendered on demand and cached in memory.
