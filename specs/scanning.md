# Scanning

## Android and iOS

**Scan** (the [Capture](navigation.md#capture) tab, or Add → Scan pages
on an event) opens the system document scanner, through
`cunning_document_scanner`: Google ML Kit's on Android, Apple VisionKit's on
iOS. It finds the page's edges in the camera image, lets the user adjust
the corners, straightens the page (perspective correction) and takes
several pages in a row; the user confirms when done. Cancelling returns
to where they were, with nothing added.

On Android the scanner runs in ML Kit's base mode: no filters to pick,
and no ML clean-up (stain and finger removal); cropping, rotating and
reordering pages remain. TabScan applies its own Tab filter. VisionKit
offers no such option, so the iOS scanner keeps its filters. Neither
scanner lets the app set the shutter: both start on auto capture, and
the user can switch to manual in the scanner.

The scanner's files are copied into the [library](library.md), then its
cache is emptied. The new event shows at the top of the list (see
[library](library.md)); it isn't opened.

Needs Android 7.0 (API 24) or later; iOS 15.5 or later (ML Kit text
recognition's minimum). iOS asks for the camera
(`NSCameraUsageDescription`: "TabScan uses the camera to scan guitar
tabs.") the first time the scanner opens it.

## Web

No document scanner: **Scan** opens TabScan's own camera screen
([lib/capture/camera_capture_screen.dart](../tabscan_app/lib/capture/camera_capture_screen.dart)),
the device's camera through the browser (`camera`, getUserMedia; the
browser asks for it the first time), the back camera first:

- a live preview, a round shutter (**Take a picture**), and the pages
  taken so far as a strip of thumbnails, several in a row, with the
  count in the title ("2 pages");
- **Flip camera** when there's more than one; **Done** (once there's a
  page) adds them; **Cancel** (×, or back) asks "Discard N pages?" first
  when there are any;
- without a camera ("No camera found.") or with it refused ("The camera
  isn't allowed: let TabScan use it in the browser's site settings."), it
  says so and offers **Choose photos instead** (the photo picker).

Pages are then cropped to the page in them, as photos added by hand are
([Cropping photos to the page](#cropping-photos-to-the-page)); when no
page stands out, they're kept as taken. Before, Scan on the web was a file
input with a camera hint, which desktop browsers show as a file chooser.

Photos already on the device are added as they are, with Capture's or an
event's **Photos & videos** or **Files** (below), not through the
scanner.

## Adding to an event

The [event screen](event-screen.md)'s **Add** asks where from, and adds the
new pages at the end, moving the view to the first one:

- **Scan pages**: more tab pages with the document scanner (as above).
- **Photos & videos**: several photos and videos from the photo library
  (`image_picker`'s multiple media picker).
- **Files**: image and video files (`file_picker`, media files): the Files
  app on iOS, the system picker on Android, the browser's on the web.
- **Link**: asks for the **Link** and an optional **Title** ("Lesson,
  recording…"). The address is trimmed and gets `https://` when it has no
  scheme (`youtu.be/abc` is `https://youtu.be/abc`); only `http` and
  `https` addresses with a host that has a dot (or `localhost`) are
  taken, anything else (`javascript:`, `file:`, `mailto:`, plain words)
  says "Enter a web address (https://…)". The title is trimmed; empty
  means none.

Picked files are recognized by extension, or else MIME type: images `jpg`,
`jpeg`, `png`, `heic`, `heif`, `webp`, `gif`; videos `mp4`, `mov`, `m4v`,
`webm`, `3gp`. Anything else is left out, and a message says how many.
Photos get the Tab filter, as scanned pages do.

### Cropping photos to the page

A photo added by hand (Photos & videos, Files; from Capture or an
event's Add), or taken with the web's camera screen, isn't straightened
by a scanner, so TabScan crops it to the
page itself, when one stands out, so what's under the page (a table, a
lap) doesn't show ([lib/processing/page_crop.dart](../tabscan_app/lib/processing/page_crop.dart),
off the UI isolate where there are isolates):

1. at 400 px (the longest side), in gray, the photo is split into bright
   and dark (Otsu's threshold), and closed a little so text and staff
   lines don't split the paper;
2. the largest bright region is the page. It must cover 20% to 92% of the
   photo, and not reach from one edge of the photo to the opposite one;
3. its corners are its extreme points along the diagonals; they must make
   a convex four-sided shape, every corner between 50° and 130°, that the
   region fills (85% to 115%);
4. the photo (turned as its EXIF says) is rectified to those corners,
   1.5% inside them so no edge of the table shows, at most 3000 px, and
   kept as a JPEG (quality 90).

When any of that fails (no clear page, the page already fills the photo,
a format the decoder can't read such as HEIC, or an error), the photo is
kept exactly as picked. Videos are never touched, nor are scanned pages
(the document scanner crops them already).
