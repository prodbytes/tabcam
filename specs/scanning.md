# Scanning

## Android and iOS

**Scan** opens the system document scanner, through
`cunning_document_scanner`: Google ML Kit's on Android, Apple VisionKit's on
iOS. It finds the page's edges in the camera image, lets the user adjust
the corners, straightens the page (perspective correction) and takes
several pages in a row; the user confirms when done. Cancelling returns
to where they were, with nothing added.

**Import photos** opens the same scanner on the photo library
(`ScannerSource.gallery`), so imported photos get edge detection and
straightening too.

The scanner's files are copied into the [library](library.md), then its
cache is emptied.

Needs Android 7.0 (API 24) or later; iOS 15.5 or later (ML Kit text
recognition's minimum). iOS asks for the camera
(`NSCameraUsageDescription`: "TabScan uses the camera to scan guitar
tabs.") the first time the scanner opens it.

## Web

No document scanner: **Scan** takes one photo with the browser's camera
input (`image_picker`; on a desktop, a file picker), and **Import photos**
picks several. Pages are kept as taken, uncropped.

## Adding pages

The [scan screen](scan-screen.md)'s **Add page** scans more pages with the
camera and adds them at the end; the view moves to the first new page.
