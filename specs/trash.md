# Deleted and Purge

Nothing the user deletes is deleted at once: it's **hidden**, and kept
(its files on the device and in the cloud) so it can be restored, until
the user presses **Purge** on the Profile tab. Purge is the only way the
app deletes the user's files.

## What goes to the trash

- **A capture** deleted (Home, a card's ⋮ menu, **Delete**,
  [library](library.md#events)) is marked `trashed` (when): hidden from
  Home, its search and studies, its pages, files and text tab all kept.
  It syncs, so it's hidden on the user's other devices too, for the
  people it's [shared](shared-captures.md) with, and for whoever opens
  its [link](sharing.md#opening-a-link) ("This capture can't be opened…",
  as a deleted one).
- **A file** deleted from a capture (the list's **Delete file**, the file
  screen's **Delete**, the play-along sidebar's Delete,
  [event screen](event-screen.md)) moves to the capture's
  `deletedPages`, with its file and its [phrase passes](cam.md#phrase-passes).
- **A file replaced**: Rotate (the image as it was) and an edited video
  put in a file's place ([video edit](video-edit.md)) keep the file it
  replaced in `deletedPages` too.

After a delete a message says so, with **Undo**: "Deleted "<name>":
restore it from Profile until you purge". The capture's delete
confirmation says where it goes ([delete confirmations](delete-confirms.md)).

Not in the trash: a capture shared with the user (Remove leaves the
share; the files are its owner's), what an owner takes back from a
published [contribution](contributions.md) (a copy: the reader's file
stays), a reader's own contribution files from before (deleted as they
were), and deleting the account ([cloud sync](cloud-sync.md#deleting-the-account)),
which deletes everything.

## Profile's Deleted

On the Profile tab, under Ask before deleting
([navigation](navigation.md#profile)): **Deleted**, what's in the trash
("1 capture, 2 files, kept until you purge them.", or "Nothing deleted.
What you delete waits here until you purge it."), with:

- **Show**: the trash screen
  ([lib/screens/trash.dart](../tabcam_app/lib/screens/trash.dart)): the
  deleted captures (the latest first, each with when it was deleted),
  then, for each capture the user still has, "Files deleted from
  "<title>"", each with **Restore**. A capture restored is shown again as
  it was; a file restored goes back at the end of its capture's files.
  "Restored "<name>"" says so. **Purge** is in its app bar too.
- **Purge**: asks, always (no Don't ask again): "Purge everything
  deleted? The deleted captures and files are deleted for good, on every
  device and in the cloud. This can't be undone." Confirmed, every
  capture in the trash is deleted for good (a tombstone once synced,
  as before), and every capture's `deletedPages` go, with their files and
  passes; then a sync pass sends it, so the cloud's copies go and the
  other devices' at their next pass. "Purged" says so.

A [clone](library.md#events) whose pages still show a file that's
purged gets a copy of its own first; one in the trash itself still shows
its original's files, which stay while the original is only in the
trash.

## Synced

`trashed` and `deletedPages` are in `event.json` ([cloud
sync](cloud-sync.md)): a deleted file's file stays in the capture's
folder (sync deletes only files no page nor deleted page names), and one
deleted before it ever went up still goes up. Deleted pages' files don't
download to other devices; restored, they come at the next pass. Someone
a capture is shared with never gets its `deletedPages`. Purged on one
device, the event comes down without them (or as a tombstone), and the
other devices delete their copies of the files.

## Verified

- Library tests: a deleted capture is hidden, files kept, and restored;
  a deleted file keeps its file and passes (through other changes) and
  is restored at the end; Rotate and a replaced video keep the old file;
  Purge deletes trashed captures (no tombstone when never synced),
  deleted files and their passes, and a clone keeps a purged original's
  file; someone else's capture brings no `deletedPages`.
- Sync tests: a deleted file stays in the folder and reaches the other
  device as deleted, restored there it's back on the first, purged it
  goes from the folder and the other device; a deleted capture is in the
  trash on every device, files kept, and purged it's a tombstone with no
  files, which a new device never gets. An owner's capture in the trash
  is hidden for the people it's shared with; purged, they leave it. Its
  link opens nothing while it's in the trash.
- Widget tests: Profile's Deleted summarizes the trash; Show lists it and
  restores a capture; Purge asks, cancelled keeps everything, confirmed
  deletes it all; a file deleted from the list says so with Undo.

## Known limitations

- An app from before the trash, on another device, doesn't know
  `trashed`: it shows a deleted capture, and saving a change to it there
  would bring it back.
- The trash isn't emptied by itself (no age limit): only Purge empties
  it, and only all of it at once.
