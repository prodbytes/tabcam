# Hidden images

The owner of a capture can hide its original images (photos and scans),
so that it shows only the text tab and its attachments (videos and links).
This is a setting on the capture, and everyone sees the capture this way:
the owner, on every device, and the people it's
[shared with](shared-captures.md).

- **Hide images** (crossed-out image icon), in the [event
  screen](event-screen.md)'s app bar, hides them; it then reads **Show
  images** (image icon) and shows them again. Only the owner has it: a
  capture shared with the user doesn't, whether it's shared to edit or
  read only. Signed out, or in builds without sync, every capture is the
  user's own, so it's always there.
- **Hidden**, the event screen's pages are first the **text tab**,
  then the videos and links in their order ("1 / 3"). The text tab page
  shows the tab, monospaced, with long lines scaled down to fit (so that
  a sideways swipe still goes to the next page), and **Open**, for the
  [text tab editor](tab-recognition.md). Before the tab has been read, it
  says "No text tab yet". Filter, Rotate and Delete are off on the text
  tab page. **Read tab** still reads the hidden images. Adding photos or
  scans adds them hidden, and says so ("Added. Images are hidden on this
  capture.").
- The images are kept, not deleted, and syncing goes on as before.
  `hideImages` is in the capture's `event.json` ([cloud
  sync](cloud-sync.md)), so the setting reaches the owner's other devices
  and the people it's shared with at the next sync pass. A
  [clone](library.md#events) keeps the setting.
- **Library**: the card has no image thumbnail (a text icon once the tab
  has been read; otherwise a video or link badge), and "images hidden"
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
