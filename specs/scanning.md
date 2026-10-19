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
reordering pages remain. TabCam applies its own Tab filter. VisionKit
offers no such option, so the iOS scanner keeps its filters. Neither
scanner lets the app set the shutter: both start on auto capture, and
the user can switch to manual in the scanner.

The scanner's files are copied into the [library](library.md), then its
cache is emptied. The new event shows at the top of the list (see
[library](library.md)); it isn't opened.

Needs Android 7.0 (API 24) or later; iOS 15.5 or later (ML Kit text
recognition's minimum). iOS asks for the camera
(`NSCameraUsageDescription`: "TabCam uses the camera to scan guitar
tabs.") the first time the scanner opens it.

On Android, ML Kit's scanner needs no permission of TabCam's. Where it
isn't there (no Google Play services), the plugin falls back to its own
cropper over a photo from the system camera app, which Android won't open
while TabCam's camera permission (declared for [Cam](cam.md)) isn't
granted. Then TabCam asks for the camera (`tabcam/camera_permission`, in
`MainActivity`) and scans again; refused, the scan fails with "Couldn't
scan: the camera isn't allowed. Let TabCam use it in the settings."

## Web

No document scanner: **Scan** opens TabCam's own camera screen
([lib/capture/camera_capture_screen.dart](../tabcam_app/lib/capture/camera_capture_screen.dart)),
the device's camera through the browser (`camera`, getUserMedia; the
browser asks for it the first time), the back camera first:

- a live preview, a round shutter (**Take a picture**), and the pages
  taken so far as a strip of thumbnails, several in a row, with the
  count in the title ("2 pages");
- **Flip camera** when there's more than one; **Done** (once there's a
  page) adds them; **Cancel** (×, or back) asks "Discard N pages?" first
  when there are any;
- without a camera ("No camera found.") or with it refused ("The camera
  isn't allowed: let TabCam use it in the browser's site settings."), it
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
new pages at the end, then shows the list of files scrolled to them (the
Add menu scrolls on a small phone):

- **Scan pages**: more tab pages with the document scanner (as above).
- **Document**: PDF files (the file picker offering only `.pdf`).
- **Photos & videos**: several photos and videos from the photo library
  (`image_picker`'s multiple media picker).
- **Files**: image, video, audio and PDF files, and zips of them
  (`file_picker`, offering the extensions below and `zip`): the Files
  app on iOS, the system picker on Android, the browser's on the web.
- **Link**: asks for the **Link** and an optional **Title** ("Lesson,
  recording…"). The address is trimmed and gets `https://` when it has no
  scheme (`youtu.be/abc` is `https://youtu.be/abc`); only `http` and
  `https` addresses with a host that has a dot (or `localhost`) are
  taken, anything else (`javascript:`, `file:`, `mailto:`, plain words)
  says "Enter a web address (https://…)". The title is trimmed; empty
  means none. A link to a known tab site also adds a PDF print of its
  page, read for tab ([tab site links](tab-site-links.md)).

Picked files are recognized by extension, or else MIME type: images `jpg`,
`jpeg`, `png`, `heic`, `heif`, `webp`, `gif`; videos `mp4`, `mov`, `m4v`,
`webm`, `3gp`; recordings `mp3`, `m4a`, `aac`, `wav`, `ogg`, `oga`,
`opus`, `flac`; and `pdf`. Anything else is left out, and a message says
how many. Photos get the Tab filter, as scanned pages do; the other files
are kept as picked.

**A zip** (`.zip`, or `application/zip`), picked or dragged onto the app,
is unzipped on the device (`MediaPick.from`,
[lib/capture/media.dart](../tabcam_app/lib/capture/media.dart)): its files
are added in its place, in its order, its folders flattened (each keeps
its own name), and a zip inside it too, one level down. macOS's
`__MACOSX` folder and hidden files (`.DS_Store`) are left out without a
word; its other files that aren't pages count among those left out, as
does a zip that can't be read, is empty, or is too big (over 1000 files
or 1 GB unzipped, by its directory).

### Cropping photos to the page

A photo added by hand (Photos & videos, Files; from Capture or an
event's Add), or taken with the web's camera screen, isn't straightened
by a scanner, so TabCam crops it to the
page itself, when one stands out, so what's under the page (a table, a
lap) doesn't show ([lib/processing/page_crop.dart](../tabcam_app/lib/processing/page_crop.dart),
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
