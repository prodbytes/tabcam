# Hidden images

The owner of a capture can hide its original images (photos and scans),
so that it shows only the text tab and its attachments (videos and links).
This is a setting on the capture, and everyone sees the capture this way:
the owner, on every device, and the people it's
[shared with](shared-captures.md).

- **No control in the app.** The [event screen](event-screen.md)'s
  app bar had a **Hide images** / **Show images** button for the owner;
  it was removed (request 44), since the bottom bar's **Text** tool
  switches between the files and the text. A capture already hidden
  stays hidden, and the app can't show its images again.
- **Hidden**, the event screen's list of files is first the **text
  tab**, then the videos, PDFs, recordings and links in their order. The
  text tab's row shows its first line, monospaced, and a tap goes to the
  [Text view](tab-recognition.md#text-view). Before the tab has been
  read, it says "No text tab yet". The hidden images are still read
  ([by itself](tab-recognition.md#reading-by-itself)). Adding photos or
  scans adds them hidden, and says so ("Added. Images are hidden on this
  capture.").
- The images are kept, not deleted, and syncing goes on as before.
  `hideImages` is in the capture's `event.json` ([cloud
  sync](cloud-sync.md)), so the setting reaches the owner's other devices
  and the people it's shared with at the next sync pass. A
  [clone](library.md#events) keeps the setting.
- **Library**: the card never shows an image: its preview is a PDF's
  first page, else the text tab's first lines once read, else a video,
  link or recording preview ([library](library.md)), and "images hidden"
  takes the place of the page count.
- **Exports** ([sharing](sharing.md)) leave the hidden images out: PDF
  has only the links and the text tab, and Files only the videos,
  `tab.txt` and `links.txt`. PDF is off when there's neither text nor a
  link, and Files when there's no video either.

## Known limitations

- Hiding is for display and export only. The images stay in the
  capture's cloud folder, and people it's shared with still sync them to
  their devices.

## Verified

`test/hide_images_test.dart`: the visible pages; the setting in the
device and cloud copies of `event.json`; a clone keeps it; the zip leaves
hidden images out; the owner hides and shows the images on the event
screen (the text tab page first); a capture shared with the user has no
toggle and shows as its owner set it.
