# Library

The home screen, titled **TabScan**.

- **Scans** show as a grid of cards, newest first: the first page's
  thumbnail (with its filter), the title, and a line with the artist (if
  set), the page count, and "text" once the tab has been read. Tapping a
  card opens the [scan screen](scan-screen.md); its ⋮ menu has **Share**
  ([sharing](sharing.md)) and **Delete** (after a confirmation, which says
  the pages and text tab go too).
- **Empty**: a music icon, "No tabs yet", and a line saying what Scan does.
- **Scan** (floating button, bottom right) opens the
  [document scanner](scanning.md); the new scan then opens. **Import
  photos** (app bar) does the same from photos on the device. **About**
  (app bar) shows the version (X.Y.Z, or "development build").
- **Theme**: Material 3, dark, from an amber seed color (`#E0A030`).

## Scans

A scan has an ID, a title, an artist (optional), when it was created, its
pages (each with an ID and a [filter](page-filters.md)), and the text tab
once read. A new scan is titled `Tab YYYY-MM-DD HH:MM` (its local time);
the scan screen's Rename changes it.

IDs are the creation time in microseconds, base 36. They name files, so
anything else (a path, say) is refused when loading.

## Storage

- **Android and iOS**: files in the app's documents folder, one folder per
  scan: `scans/<scan id>/scan.json` (the details) and `<page id>.img` per
  page, the image as scanned. `scan.json` is written beside and renamed
  over, so a crash never leaves half a file. A scan whose `scan.json`
  can't be read is skipped, not fatal.
- **Web**: in memory; scans last until the tab is closed.

Filtered pages are rendered on demand and cached in memory.
